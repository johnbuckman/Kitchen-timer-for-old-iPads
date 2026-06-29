#import "ViewController.h"
#import <AudioToolbox/AudioToolbox.h>

#define NCOUNT 2          // 2 stopwatches, 2 countdown timers -> 2x2 grid
#define CD_MAX_MIN 5940   // cap a countdown at 99 hours (so keypad entries like "8h" aren't clamped)
#define DING_SOUND 1005   // "nice ding" alert tone (try 1013 / 1057 'Tink' to taste)
#define DING_EVERY 5      // re-ding every N seconds while in overtime
#define IDLE_LIMIT 3600        // seconds of no interaction before the screensaver shows (1 hour)

@interface ViewController () <UIGestureRecognizerDelegate>
{
    NSTimer *_master;            // single 1s tick driving everything
    NSDateFormatter *_clockFmt;

    UILabel *_clock;
    UILabel *_dayMain;   // weekday under the clock (grey, smaller)
    UIStackView *_clockStack;   // [clock, day] — spacing tuned per orientation
    UIView   *_clockRow;        // top row holding the clock pill
    UIStackView *_topRow, *_botRow;          // the two grid rows
    NSLayoutConstraint *_topRowH, *_botRowH; // their heights (computed each layout)

    // Stopwatches (count UP)
    int      _swSeconds[NCOUNT];
    BOOL     _swRunning[NCOUNT];
    UILabel *_swValue[NCOUNT];
    UILabel *_swTitle[NCOUNT];
    UIButton *_swToggle[NCOUNT];
    UIButton *_swReset[NCOUNT];
    NSString *_swStartStr[NCOUNT];   // wall-clock time the stopwatch was started

    // Countdown timers (count DOWN)
    int      _cdRemaining[NCOUNT]; // seconds remaining
    int      _cdSetSec[NCOUNT];    // duration (seconds) the user dialed in
    BOOL     _cdRunning[NCOUNT];
    UILabel *_cdValue[NCOUNT];
    UILabel *_cdTitle[NCOUNT];
    UIButton *_cdToggle[NCOUNT];
    UIButton *_cdReset[NCOUNT];
    UIButton *_cdPlusBtn[NCOUNT];
    UIButton *_cdMinusBtn[NCOUNT];
    NSString *_cdStartStr[NCOUNT];   // wall-clock time the countdown was started
    int      _cdStartDurSec[NCOUNT]; // duration (seconds) it had when started

    // Press-and-hold auto-repeat for the +/- buttons
    NSTimer *_holdTimer;
    int      _holdIndex;
    int      _holdSign;   // +1 or -1
    int      _holdReps;

    // Full-screen time-entry keypad
    UIView      *_keypad;
    UILabel     *_entryDisplay;
    NSMutableString *_entryText;
    int          _keypadKind;   // 0 = count-up (stopwatch), 1 = count-down
    int          _keypadIndex;
    NSArray     *_unitKeys;     // the hours/minutes/seconds keys (font shrinks in landscape)

    BOOL _pulsing;   // YES while the overtime black<->white flash is running

    // Idle / screensaver
    int      _idleSeconds;
    UIView  *_screensaver;
    UIView  *_ssGroup;     // time + day + logo, moved together for burn-in protection
    UILabel *_ssTime;
    UILabel *_ssDay;       // weekday under the time
    UIImageView *_ssLogo;  // decent logo under the day
    int      _ssSeconds;   // seconds the screensaver has been showing
    int      _ssShiftIndex;// which vertical offset we're on
    NSDateFormatter *_dayFmt;
}
@end

@implementation ViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _clockFmt = [[NSDateFormatter alloc] init];
    _clockFmt.dateFormat = @"H:mm";

    _dayFmt = [[NSDateFormatter alloc] init];
    _dayFmt.dateFormat = @"EEEE";   // full weekday name, e.g. "Monday"

    for (int i = 0; i < NCOUNT; i++) {
        _cdSetSec[i] = 5 * 60;
        _cdRemaining[i] = _cdSetSec[i];
    }

    [self buildUI];
    [self refreshAll];

    _master = [NSTimer scheduledTimerWithTimeInterval:1.0
                                               target:self
                                             selector:@selector(tick)
                                             userInfo:nil
                                              repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_master forMode:NSRunLoopCommonModes];
}

- (BOOL)prefersStatusBarHidden { return YES; }

// Per-orientation tweak: the clock + weekday sizes.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (!_dayMain || !_clock) return;
    BOOL landscape = self.view.bounds.size.width > self.view.bounds.size.height;

    // Portrait's bigger clock has more internal leading, so tuck the weekday up tighter there.
    _clockStack.spacing = landscape ? -6.0 : -34.0;

    if (_unitKeys) [self updateKeypadUnitFont];   // keypad hours/min/sec font per orientation

    // Clock: 108pt landscape / 162pt portrait. The weekday tracks at a quarter the clock
    // size. Guard so we don't re-invalidate layout every pass.
    CGFloat clockSize = landscape ? 108.0 : 162.0;
    if (_clock.font.pointSize != clockSize) {
        _clock.font   = [UIFont monospacedDigitSystemFontOfSize:clockSize weight:UIFontWeightBold];
        _dayMain.font = [UIFont monospacedDigitSystemFontOfSize:clockSize / 4.0 weight:UIFontWeightBold];
    }
}

// Size the two grid rows so they fill from below the clock to the bottom (constant heights
// are honored where relational fill constraints aren't, on iOS 26).
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!_topRowH || !_clockRow) return;
    CGFloat avail = self.view.bounds.size.height - 24 - 24;     // top + bottom insets
    CGFloat clockH = CGRectGetHeight(_clockRow.frame);
    CGFloat rowH = (avail - clockH - 18 - 18) / 2.0;            // two 18pt gaps
    if (rowH > 40 && fabs(_topRowH.constant - rowH) > 0.5) {
        _topRowH.constant = rowH;
        _botRowH.constant = rowH;
    }
}

#pragma mark - UI construction

- (void)buildUI {
    // The clock row sits at the top and the 2x2 grid fills everything below it, pinned to
    // the bottom — explicit constraints (a UIStackView left the grid un-stretched, bunching
    // everything in the vertical center with big empty bands on tall screens).

    // --- Clock (+ weekday) in a dark "pill" so it stays readable while the bg pulses ---
    _clock = [[UILabel alloc] init];
    _clock.font = [UIFont monospacedDigitSystemFontOfSize:108 weight:UIFontWeightBold];
    _clock.textColor = [UIColor whiteColor];
    _clock.textAlignment = NSTextAlignmentCenter;
    _clock.text = @"--:--";
    // Shrink the time to fit rather than truncate it on narrow screens (e.g. the iPad mini 1
    // in portrait, where 162pt was too wide).
    _clock.adjustsFontSizeToFitWidth = YES;
    _clock.minimumScaleFactor = 0.4;

    // Weekday: grey, a quarter the clock's size (size set per orientation in
    // viewWillLayoutSubviews). 27 = a quarter of the 108pt landscape clock.
    _dayMain = [[UILabel alloc] init];
    _dayMain.font = [UIFont monospacedDigitSystemFontOfSize:27 weight:UIFontWeightBold];
    _dayMain.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    _dayMain.textAlignment = NSTextAlignmentCenter;
    _dayMain.text = [_dayFmt stringFromDate:[NSDate date]];   // non-empty at first layout
    _dayMain.adjustsFontSizeToFitWidth = YES;
    _dayMain.minimumScaleFactor = 0.4;

    // Time + weekday stacked in the pill; spacing tuned per orientation in viewWillLayoutSubviews.
    _clockStack = [[UIStackView alloc] initWithArrangedSubviews:@[ _clock, _dayMain ]];
    _clockStack.axis = UILayoutConstraintAxisVertical;
    _clockStack.alignment = UIStackViewAlignmentCenter;
    _clockStack.spacing = -6;
    _clockStack.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *pill = [[UIView alloc] init];
    pill.backgroundColor = [UIColor blackColor];   // invisible on black; readable during the white pulse
    pill.layer.cornerRadius = 32;
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    [pill addSubview:_clockStack];
    // Tap the time to start the screensaver immediately.
    [pill addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(clockTapped)]];

    _clockRow = [[UIView alloc] init];   // full-width row that centers the pill
    [_clockRow addSubview:pill];
    [_clockRow setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    _clockRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_clockRow];

    [NSLayoutConstraint activateConstraints:@[
        [pill.centerXAnchor constraintEqualToAnchor:_clockRow.centerXAnchor],
        [pill.topAnchor constraintEqualToAnchor:_clockRow.topAnchor],
        [pill.bottomAnchor constraintEqualToAnchor:_clockRow.bottomAnchor],
        [pill.leadingAnchor constraintGreaterThanOrEqualToAnchor:_clockRow.leadingAnchor],
        [pill.trailingAnchor constraintLessThanOrEqualToAnchor:_clockRow.trailingAnchor],
        [_clockStack.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:48],
        [_clockStack.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-48],
        [_clockStack.topAnchor constraintEqualToAnchor:pill.topAnchor constant:14],
        [_clockStack.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-18],
    ]];

    // --- 2x2 grid. Two equal rows, heights computed each layout in viewDidLayoutSubviews
    // (relational "fill" constraints don't stretch the rows on iOS 26; constant heights do).
    _topRow = [self gridRow:@[ [self stopwatchCard:0], [self stopwatchCard:1] ]];
    _botRow = [self gridRow:@[ [self countdownCard:0], [self countdownCard:1] ]];
    _topRow.translatesAutoresizingMaskIntoConstraints = NO;
    _botRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_topRow];
    [self.view addSubview:_botRow];

    _topRowH = [_topRow.heightAnchor constraintEqualToConstant:200];
    _botRowH = [_botRow.heightAnchor constraintEqualToConstant:200];
    [NSLayoutConstraint activateConstraints:@[
        [_clockRow.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:24],
        [_clockRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
        [_clockRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
        [_topRow.topAnchor constraintEqualToAnchor:_clockRow.bottomAnchor constant:18],
        [_topRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
        [_topRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
        [_botRow.topAnchor constraintEqualToAnchor:_topRow.bottomAnchor constant:18],
        [_botRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
        [_botRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
        _topRowH, _botRowH,
    ]];

    [self buildScreensaver];   // full-screen overlay, on top, hidden until idle
}

- (void)buildScreensaver {
    _screensaver = [[UIView alloc] init];
    _screensaver.backgroundColor = [UIColor blackColor];
    _screensaver.hidden = YES;
    _screensaver.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_screensaver];

    // Time + logo live in a group so we can shift them together to dodge burn-in.
    _ssGroup = [[UIView alloc] init];
    _ssGroup.translatesAutoresizingMaskIntoConstraints = NO;
    [_screensaver addSubview:_ssGroup];

    _ssTime = [[UILabel alloc] init];
    _ssTime.font = [UIFont monospacedDigitSystemFontOfSize:360 weight:UIFontWeightBold];
    _ssTime.textColor = [UIColor whiteColor];
    _ssTime.textAlignment = NSTextAlignmentCenter;
    _ssTime.adjustsFontSizeToFitWidth = YES;
    _ssTime.minimumScaleFactor = 0.2;
    _ssTime.translatesAutoresizingMaskIntoConstraints = NO;
    [_ssGroup addSubview:_ssTime];

    // Weekday: grey (same 0.6 grey as the main-display weekday), bold, 120pt.
    _ssDay = [[UILabel alloc] init];
    _ssDay.font = [UIFont monospacedDigitSystemFontOfSize:120 weight:UIFontWeightBold];
    _ssDay.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    _ssDay.textAlignment = NSTextAlignmentCenter;
    _ssDay.adjustsFontSizeToFitWidth = YES;
    _ssDay.minimumScaleFactor = 0.3;
    _ssDay.translatesAutoresizingMaskIntoConstraints = NO;
    [_ssGroup addSubview:_ssDay];

    _ssLogo = [[UIImageView alloc] init];
    _ssLogo.image = [UIImage imageNamed:@"decent_logo"];
    _ssLogo.contentMode = UIViewContentModeScaleAspectFit;
    _ssLogo.alpha = 0.25;   // quite transparent
    _ssLogo.translatesAutoresizingMaskIntoConstraints = NO;
    [_ssGroup addSubview:_ssLogo];

    CGFloat logoAspect = 654.0 / 1748.0;   // height / width of the source PNG
    [NSLayoutConstraint activateConstraints:@[
        [_screensaver.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_screensaver.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_screensaver.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_screensaver.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        // Group spans the width (so the time can shrink-to-fit) and is centered.
        [_ssGroup.leadingAnchor constraintEqualToAnchor:_screensaver.leadingAnchor constant:24],
        [_ssGroup.trailingAnchor constraintEqualToAnchor:_screensaver.trailingAnchor constant:-24],
        [_ssGroup.centerYAnchor constraintEqualToAnchor:_screensaver.centerYAnchor],
        // Time across the top of the group.
        [_ssTime.topAnchor constraintEqualToAnchor:_ssGroup.topAnchor],
        [_ssTime.leadingAnchor constraintEqualToAnchor:_ssGroup.leadingAnchor],
        [_ssTime.trailingAnchor constraintEqualToAnchor:_ssGroup.trailingAnchor],
        // Weekday pulled up close under the time (negative offset overcomes the font's
        // internal leading so the gap actually shrinks visibly).
        [_ssDay.topAnchor constraintEqualToAnchor:_ssTime.bottomAnchor constant:-30],
        [_ssDay.centerXAnchor constraintEqualToAnchor:_ssGroup.centerXAnchor],
        // Logo under the day (0.30 of the time's width).
        [_ssLogo.topAnchor constraintEqualToAnchor:_ssDay.bottomAnchor constant:30],
        [_ssLogo.centerXAnchor constraintEqualToAnchor:_ssGroup.centerXAnchor],
        [_ssLogo.widthAnchor constraintEqualToAnchor:_ssTime.widthAnchor multiplier:0.30],
        [_ssLogo.heightAnchor constraintEqualToAnchor:_ssLogo.widthAnchor multiplier:logoAspect],
        [_ssLogo.bottomAnchor constraintEqualToAnchor:_ssGroup.bottomAnchor],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(screensaverTapped)];
    [_screensaver addGestureRecognizer:tap];
}

- (UIStackView *)gridRow:(NSArray *)cards {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:cards];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 18;
    // Let the row be stretched vertically to fill (otherwise its high default hugging
    // resists the fill-to-bottom constraint and the layout bunches in the center).
    [row setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    return row;
}

- (UIView *)cardContainer:(UIStackView *)content {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    card.layer.cornerRadius = 16;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];
    return card;
}

- (UILabel *)cardTitle:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    l.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    l.textAlignment = NSTextAlignmentCenter;
    l.adjustsFontSizeToFitWidth = YES;   // the running "started at … ETA …" text is long
    l.minimumScaleFactor = 0.45;
    l.numberOfLines = 1;
    [l setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    return l;
}

- (UILabel *)bigValueLabel {
    UILabel *l = [[UILabel alloc] init];
    l.font = [UIFont monospacedDigitSystemFontOfSize:84 weight:UIFontWeightBold];
    l.textColor = [UIColor whiteColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.4;
    [l setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    return l;
}

// Large, easy-to-tap button (min height 64).
- (UIButton *)bigButton:(NSString *)title color:(UIColor *)color
                 action:(SEL)action tag:(int)tag fontSize:(CGFloat)fs {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:fs weight:UIFontWeightSemibold];
    b.backgroundColor = color;
    b.layer.cornerRadius = 12;
    b.tag = tag;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [b.heightAnchor constraintGreaterThanOrEqualToConstant:64].active = YES;
    return b;
}

- (UIStackView *)buttonRow:(NSArray *)buttons {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 14;
    // Fixed, tall tap targets — and keeps every card's action row identical height.
    [row.heightAnchor constraintEqualToConstant:78].active = YES;
    [row setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    return row;
}

- (UIView *)stopwatchCard:(int)i {
    _swValue[i] = [self bigValueLabel];

    _swToggle[i] = [self bigButton:@"Up"
                             color:[self greenColor] action:@selector(swToggle:) tag:i fontSize:26];
    _swReset[i] = [self bigButton:@"Reset"
                            color:[self grayColor] action:@selector(swReset:) tag:i fontSize:26];

    _swTitle[i] = [self cardTitle:@"Count up"];
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[
        _swTitle[i],
        _swValue[i],
        [self buttonRow:@[ _swToggle[i], _swReset[i] ]] ]];
    content.axis = UILayoutConstraintAxisVertical;
    content.alignment = UIStackViewAlignmentFill;
    content.distribution = UIStackViewDistributionFill;
    content.spacing = 14;

    UIView *card = [self cardContainer:content];
    card.tag = i;   // stopwatch i  (countdown cards use 100+i)
    [self addKeypadTapTo:card];
    return card;
}

- (UIView *)countdownCard:(int)i {
    _cdValue[i] = [self bigValueLabel];

    // TouchUpInside -> cdHoldEnd (a normal tap is one ±1 step from the TouchDown handler,
    // then this stops the hold). TouchDown begins the step + auto-repeat.
    _cdMinusBtn[i] = [self bigButton:@"–" color:[self grayColor] action:@selector(cdHoldEnd:) tag:i fontSize:42];
    _cdPlusBtn[i]  = [self bigButton:@"+" color:[self grayColor] action:@selector(cdHoldEnd:) tag:i fontSize:42];
    for (UIButton *b in @[ _cdMinusBtn[i], _cdPlusBtn[i] ]) {
        [b.widthAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
        [b setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [b addTarget:self action:@selector(cdHoldBegin:) forControlEvents:UIControlEventTouchDown];
        [b addTarget:self action:@selector(cdHoldEnd:)
            forControlEvents:(UIControlEventTouchUpOutside | UIControlEventTouchCancel)];
    }

    UIStackView *setRow = [[UIStackView alloc] initWithArrangedSubviews:@[ _cdMinusBtn[i], _cdValue[i], _cdPlusBtn[i] ]];
    setRow.axis = UILayoutConstraintAxisHorizontal;
    setRow.alignment = UIStackViewAlignmentCenter;   // keep -/+ a sane size; let the number be big
    setRow.distribution = UIStackViewDistributionFill;
    setRow.spacing = 14;
    [setRow setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];

    _cdToggle[i] = [self bigButton:@"Down"
                             color:[self blueColor] action:@selector(cdToggle:) tag:i fontSize:26];
    _cdReset[i] = [self bigButton:@"Reset"
                            color:[self grayColor] action:@selector(cdReset:) tag:i fontSize:26];

    _cdTitle[i] = [self cardTitle:@"Count down"];
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[
        _cdTitle[i],
        setRow,
        [self buttonRow:@[ _cdToggle[i], _cdReset[i] ]] ]];
    content.axis = UILayoutConstraintAxisVertical;
    content.alignment = UIStackViewAlignmentFill;
    content.distribution = UIStackViewDistributionFill;
    content.spacing = 14;

    UIView *card = [self cardContainer:content];
    card.tag = 100 + i;   // countdown i  (stopwatch cards use i)
    [self addKeypadTapTo:card];
    return card;
}

// Tap the card body (not a button) to open the keypad; buttons keep their normal taps.
- (void)addKeypadTapTo:(UIView *)card {
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
    tap.delegate = self;
    [card addGestureRecognizer:tap];
}

// Don't let the card tap fire when the touch lands on a button.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIControl class]];
}

#pragma mark - Colors

- (UIColor *)greenColor { return [UIColor colorWithRed:0.20 green:0.55 blue:0.30 alpha:1.0]; }
- (UIColor *)redColor   { return [UIColor colorWithRed:0.70 green:0.25 blue:0.20 alpha:1.0]; }
- (UIColor *)blueColor  { return [UIColor colorWithRed:0.20 green:0.45 blue:0.70 alpha:1.0]; }
- (UIColor *)grayColor  { return [UIColor colorWithWhite:0.32 alpha:1.0]; }
- (UIColor *)orangeColor{ return [UIColor colorWithRed:1.0 green:0.55 blue:0.0 alpha:1.0]; }
- (UIColor *)dimColor   { return [UIColor colorWithWhite:0.5 alpha:1.0]; }   // inactive time text

#pragma mark - Tick

- (void)tick {
    NSDate *now = [NSDate date];
    _clock.text   = [_clockFmt stringFromDate:now];
    _dayMain.text = [_dayFmt stringFromDate:now];

    for (int i = 0; i < NCOUNT; i++) {
        if (_swRunning[i]) { _swSeconds[i]++; [self refreshStopwatch:i]; }
    }
    for (int i = 0; i < NCOUNT; i++) {
        if (_cdRunning[i]) {
            _cdRemaining[i]--;
            // Ding the moment it hits zero, then re-ding every DING_EVERY seconds in overtime,
            // until the countdown is stopped/reset.
            if (_cdRemaining[i] <= 0 && (_cdRemaining[i] % DING_EVERY == 0)) {
                AudioServicesPlaySystemSound(DING_SOUND);
            }
            [self refreshCountdown:i];
        }
    }
    [self updatePulse];

    // --- idle / screensaver ---
    _idleSeconds++;
    // Never sleep while a timer is running or the time-entry keypad is open.
    BOOL active = [self anyTimerActive] || (_keypad && !_keypad.hidden);
    if (!_screensaver.hidden) {
        if (active) {
            [self hideScreensaver];
        } else {
            [self updateScreensaver];
            // Shift the time+logo every minute (up/down, still centered) for burn-in.
            _ssSeconds++;
            if (_ssSeconds % 60 == 0) { _ssShiftIndex++; [self applyScreensaverShift]; }
        }
    } else if (_idleSeconds >= IDLE_LIMIT && !active) {
        [self showScreensaver];
    }
}

- (BOOL)anyTimerActive {
    for (int i = 0; i < NCOUNT; i++)
        if (_swRunning[i] || _cdRunning[i]) return YES;
    return NO;
}

#pragma mark - Stopwatch actions

- (void)swToggle:(UIButton *)b {
    int i = (int)b.tag;
    [self resetIdle];
    _swRunning[i] = !_swRunning[i];
    if (_swRunning[i]) _swStartStr[i] = [_clockFmt stringFromDate:[NSDate date]];
    [b setTitle:(_swRunning[i] ? @"Stop" : @"Up") forState:UIControlStateNormal];
    b.backgroundColor = _swRunning[i] ? [self redColor] : [self greenColor];
    [self refreshStopwatch:i];   // updates the title + show/hide Reset right away
}

- (void)swReset:(UIButton *)b {
    int i = (int)b.tag;
    [self resetIdle];
    _swRunning[i] = NO;
    _swSeconds[i] = 0;
    [_swToggle[i] setTitle:@"Up" forState:UIControlStateNormal];
    _swToggle[i].backgroundColor = [self greenColor];
    [self refreshStopwatch:i];
}

#pragma mark - Countdown actions

// One +/- step of `mins` minutes. Stopped -> edits the set duration; running -> edits the
// time remaining (floored at 0, capped at CD_MAX_MIN; never forces overtime).
- (void)cdStep:(int)i sign:(int)s minutes:(int)mins {
    int delta = s * mins * 60;
    if (_cdRunning[i]) {
        _cdRemaining[i] += delta;
    } else {
        _cdSetSec[i] += delta;
        if (_cdSetSec[i] < 0) _cdSetSec[i] = 0;
        if (_cdSetSec[i] > CD_MAX_MIN * 60) _cdSetSec[i] = CD_MAX_MIN * 60;
        _cdRemaining[i] = _cdSetSec[i];
    }
    if (_cdRemaining[i] < 0) _cdRemaining[i] = 0;
    if (_cdRemaining[i] > CD_MAX_MIN * 60) _cdRemaining[i] = CD_MAX_MIN * 60;
    [self refreshCountdown:i];
    [self updatePulse];
}

// TouchDown on +/-: one immediate ±1, then start auto-repeat (kicks into fast mode if held).
- (void)cdHoldBegin:(UIButton *)b {
    int i = (int)b.tag;
    [self resetIdle];
    [_holdTimer invalidate];
    _holdIndex = i;
    _holdSign  = (b == _cdPlusBtn[i]) ? +1 : -1;
    _holdReps  = 0;
    [self cdStep:i sign:_holdSign minutes:1];   // the single-tap change
    _holdTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                  target:self selector:@selector(holdFire)
                                                userInfo:nil repeats:YES];
}

// Fires every 0.1s while a +/- is held. First ~0.3s is a grace period (so a normal tap
// stays a single step); after that it changes fast, accelerating the longer you hold.
- (void)holdFire {
    _holdReps++;
    if (_holdReps < 3) return;            // grace: ~0.3s before fast-change engages
    int r = _holdReps - 3;
    int step = (r < 10) ? 2 : (r < 25 ? 5 : 10);
    [self cdStep:_holdIndex sign:_holdSign minutes:step];
}

- (void)cdHoldEnd:(UIButton *)b {
    [_holdTimer invalidate];
    _holdTimer = nil;
}

- (void)cdToggle:(UIButton *)b {
    int i = (int)b.tag;
    [self resetIdle];
    if (!_cdRunning[i]) {
        if (_cdRemaining[i] <= 0) _cdRemaining[i] = _cdSetSec[i];
        if (_cdRemaining[i] <= 0) return;
        _cdRunning[i] = YES;
        _cdStartStr[i] = [_clockFmt stringFromDate:[NSDate date]];
        _cdStartDurSec[i] = _cdRemaining[i];   // original duration when started
        [b setTitle:@"Stop" forState:UIControlStateNormal];
        b.backgroundColor = [self redColor];
    } else {
        _cdRunning[i] = NO;
        [b setTitle:@"Down" forState:UIControlStateNormal];
        b.backgroundColor = [self blueColor];
    }
    [self refreshCountdown:i];   // show/hide Reset right away
    [self updatePulse];   // stopping an overtime countdown should end the flash at once
}

- (void)cdReset:(UIButton *)b {
    int i = (int)b.tag;
    [self resetIdle];
    _cdRunning[i] = NO;
    _cdRemaining[i] = _cdSetSec[i];
    [_cdToggle[i] setTitle:@"Down" forState:UIControlStateNormal];
    _cdToggle[i].backgroundColor = [self blueColor];
    [self refreshCountdown:i];
    [self updatePulse];   // reset clears overtime -> end the flash
}

#pragma mark - Display

- (void)refreshAll {
    for (int i = 0; i < NCOUNT; i++) { [self refreshStopwatch:i]; [self refreshCountdown:i]; }
}

// M:SS under an hour; once it reaches an hour, H:MM:SS (minutes/seconds zero-padded to
// two digits). Handles negative (overtime) values, e.g. "-0:07".
- (NSString *)mmss:(int)totalSeconds {
    NSString *sign = (totalSeconds < 0) ? @"-" : @"";
    int s = (totalSeconds < 0) ? -totalSeconds : totalSeconds;
    int h = s / 3600, m = (s % 3600) / 60, sec = s % 60;
    if (h > 0) return [NSString stringWithFormat:@"%@%d:%02d:%02d", sign, h, m, sec];
    return [NSString stringWithFormat:@"%@%d:%02d", sign, m, sec];
}

- (void)refreshStopwatch:(int)i {
    _swValue[i].text = [self mmss:_swSeconds[i]];
    // Grey while inactive, white while running.
    _swValue[i].textColor = _swRunning[i] ? [UIColor whiteColor] : [self dimColor];
    // Title: "Count up started at XX:XX" while running, else just "Count up".
    _swTitle[i].text = _swRunning[i]
        ? [NSString stringWithFormat:@"Started at %@", _swStartStr[i]]
        : @"Count up";
    // Reset only matters once it's running or has counted something.
    _swReset[i].hidden = (!_swRunning[i] && _swSeconds[i] == 0);
}

- (void)refreshCountdown:(int)i {
    _cdValue[i].text = [self mmss:_cdRemaining[i]];
    // Grey while inactive; white while running; orange while running past zero (alarm).
    if (!_cdRunning[i])              _cdValue[i].textColor = [self dimColor];
    else if (_cdRemaining[i] <= 0)   _cdValue[i].textColor = [self orangeColor];
    else                             _cdValue[i].textColor = [UIColor whiteColor];
    // Title: "Count down started at <start>, ETA <eta>" while running, else "Count down".
    // ETA = now + time remaining (recomputed each tick so +/- adjustments move it).
    if (_cdRunning[i]) {
        NSDate *eta = [NSDate dateWithTimeIntervalSinceNow:_cdRemaining[i]];
        _cdTitle[i].text = [NSString stringWithFormat:@"Started at %@, ETA %@",
                            _cdStartStr[i], [_clockFmt stringFromDate:eta]];
    } else {
        _cdTitle[i].text = @"Count down";
    }
    // Reset only matters once it's running or no longer at its freshly-set value.
    _cdReset[i].hidden = (!_cdRunning[i] && _cdRemaining[i] == _cdSetSec[i]);
}

#pragma mark - Overtime pulse

// Start/stop the background flash based on whether any countdown is at/under zero.
- (void)updatePulse {
    BOOL anyOvertime = NO;
    for (int i = 0; i < NCOUNT; i++) {
        if (_cdRunning[i] && _cdRemaining[i] <= 0) { anyOvertime = YES; break; }
    }
    if (anyOvertime && !_pulsing) { _pulsing = YES; [self startPulse]; }
    else if (!anyOvertime && _pulsing) { _pulsing = NO; [self stopPulse]; }
}

- (void)startPulse {
    self.view.backgroundColor = [UIColor blackColor];
    // 1s black->white, autoreverse 1s white->black, repeat forever, smooth ease.
    // AllowUserInteraction so Stop/Reset still work while it flashes.
    [UIView animateWithDuration:1.0
                          delay:0
                        options:(UIViewAnimationOptionRepeat |
                                 UIViewAnimationOptionAutoreverse |
                                 UIViewAnimationOptionCurveEaseInOut |
                                 UIViewAnimationOptionAllowUserInteraction)
                     animations:^{ self.view.backgroundColor = [UIColor whiteColor]; }
                     completion:nil];
}

- (void)stopPulse {
    [self.view.layer removeAllAnimations];
    self.view.backgroundColor = [UIColor blackColor];
}

#pragma mark - Screensaver / idle

// Any interaction (button, scrub, or a tap on empty space / the screensaver) calls this.
- (void)resetIdle {
    _idleSeconds = 0;
    if (_screensaver && !_screensaver.hidden) [self hideScreensaver];
}

- (void)showScreensaver {
    [self updateScreensaver];
    _ssSeconds = 0;
    _ssShiftIndex = 0;
    _ssGroup.transform = CGAffineTransformIdentity;
    _screensaver.hidden = NO;
    [self.view bringSubviewToFront:_screensaver];
}

- (void)hideScreensaver { _screensaver.hidden = YES; }

- (void)updateScreensaver {
    NSDate *now = [NSDate date];
    _ssTime.text = [_clockFmt stringFromDate:now];
    _ssDay.text  = [_dayFmt stringFromDate:now];
}

// Once a minute, slide the time+logo to a new vertical offset (still horizontally
// centered) so no pixel is lit in the same spot for long — anti burn-in.
- (void)applyScreensaverShift {
    static const CGFloat offsets[] = { 0, -60, 0, 60 };   // up / center / down / center
    CGFloat dy = offsets[_ssShiftIndex % 4];
    [UIView animateWithDuration:2.0 delay:0 options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ _ssGroup.transform = CGAffineTransformMakeTranslation(0, dy); }
                     completion:nil];
}

- (void)screensaverTapped { [self resetIdle]; }

// Tapping the clock starts the screensaver on demand.
- (void)clockTapped { [self showScreensaver]; }

// Catches taps on empty space / cards (button taps reset idle in their own handlers).
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self resetIdle];
    [super touchesBegan:touches withEvent:event];
}

#pragma mark - Time-entry keypad

// Tap a card body (not a button). If that timer hasn't started, open the keypad.
- (void)cardTapped:(UITapGestureRecognizer *)g {
    int t = (int)g.view.tag;
    BOOL isCd = (t >= 100);
    int i = isCd ? (t - 100) : t;
    [self resetIdle];
    BOOL running = isCd ? _cdRunning[i] : _swRunning[i];
    if (running) return;             // only before it's started
    _keypadKind = isCd ? 1 : 0;
    _keypadIndex = i;
    [self showKeypad];
}

- (void)showKeypad {
    if (!_keypad) [self buildKeypad];
    _entryText = [NSMutableString string];
    [self refreshEntryDisplay];
    _keypad.hidden = NO;
    [self.view bringSubviewToFront:_keypad];
}

- (void)hideKeypad { _keypad.hidden = YES; }

- (void)buildKeypad {
    _keypad = [[UIView alloc] init];
    _keypad.backgroundColor = [UIColor blackColor];
    _keypad.hidden = YES;
    _keypad.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_keypad];

    _entryDisplay = [[UILabel alloc] init];
    _entryDisplay.font = [UIFont monospacedDigitSystemFontOfSize:96 weight:UIFontWeightBold];
    _entryDisplay.textColor = [UIColor whiteColor];
    _entryDisplay.textAlignment = NSTextAlignmentCenter;
    _entryDisplay.adjustsFontSizeToFitWidth = YES;
    _entryDisplay.minimumScaleFactor = 0.3;
    [_entryDisplay setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

    // 4x4 of digits + ':' '.' and hours/minutes/seconds units + backspace.
    NSArray *rows = @[ @[ @"7", @"8", @"9", @"hours" ],
                       @[ @"4", @"5", @"6", @"minutes" ],
                       @[ @"1", @"2", @"3", @"seconds" ],
                       @[ @".", @"0", @":", @"⌫" ] ];   // ⌫
    UIStackView *grid = [[UIStackView alloc] init];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.distribution = UIStackViewDistributionFillEqually;
    grid.spacing = 12;
    NSMutableArray *units = [NSMutableArray array];
    for (NSArray *row in rows) {
        UIStackView *r = [[UIStackView alloc] init];
        r.axis = UILayoutConstraintAxisHorizontal;
        r.distribution = UIStackViewDistributionFillEqually;
        r.spacing = 12;
        for (NSString *k in row) {
            UIButton *key = [self keypadKey:k];
            if ([k isEqualToString:@"hours"] || [k isEqualToString:@"minutes"] || [k isEqualToString:@"seconds"])
                [units addObject:key];
            [r addArrangedSubview:key];
        }
        [grid addArrangedSubview:r];
    }
    _unitKeys = units;
    [self updateKeypadUnitFont];   // size them for the current orientation

    UIButton *cancel = [self keypadActionButton:@"Cancel" color:[self grayColor]  action:@selector(keypadCancel)];
    UIButton *done   = [self keypadActionButton:@"Done"   color:[self greenColor] action:@selector(keypadDone)];
    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[ cancel, done ]];
    bottom.axis = UILayoutConstraintAxisHorizontal;
    bottom.distribution = UIStackViewDistributionFillEqually;
    bottom.spacing = 12;
    [bottom setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

    UIStackView *outer = [[UIStackView alloc] initWithArrangedSubviews:@[ _entryDisplay, grid, bottom ]];
    outer.axis = UILayoutConstraintAxisVertical;
    outer.spacing = 20;
    outer.translatesAutoresizingMaskIntoConstraints = NO;
    [_keypad addSubview:outer];

    [NSLayoutConstraint activateConstraints:@[
        [_keypad.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_keypad.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_keypad.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_keypad.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [outer.leadingAnchor constraintEqualToAnchor:_keypad.leadingAnchor constant:48],
        [outer.trailingAnchor constraintEqualToAnchor:_keypad.trailingAnchor constant:-48],
        [outer.topAnchor constraintEqualToAnchor:_keypad.topAnchor constant:40],
        [outer.bottomAnchor constraintEqualToAnchor:_keypad.bottomAnchor constant:-40],
        // Fixed display + short bottom-row height so the key grid gets most of the screen.
        [_entryDisplay.heightAnchor constraintEqualToConstant:140],
        [bottom.heightAnchor constraintEqualToConstant:104],
    ]];
}

// Short flat action button for the keypad (Cancel/Done) — no tall min-height.
- (UIButton *)keypadActionButton:(NSString *)title color:(UIColor *)c action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:48 weight:UIFontWeightSemibold];
    b.backgroundColor = c;
    b.layer.cornerRadius = 12;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIButton *)keypadKey:(NSString *)title {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:44 weight:UIFontWeightSemibold];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;   // so "minutes"/"seconds" fit
    b.titleLabel.minimumScaleFactor = 0.4;
    b.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    b.layer.cornerRadius = 12;
    [b addTarget:self action:@selector(keypadKeyTapped:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// hours/minutes/seconds keys: 30% smaller font in landscape (44 -> ~31), full size portrait.
- (void)updateKeypadUnitFont {
    BOOL landscape = self.view.bounds.size.width > self.view.bounds.size.height;
    CGFloat size = landscape ? 31.0 : 44.0;
    for (UIButton *b in _unitKeys)
        b.titleLabel.font = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
}

- (void)keypadKeyTapped:(UIButton *)b {
    [self resetIdle];
    NSString *k = b.currentTitle;
    if ([k isEqualToString:@"⌫"]) {                          // backspace
        if (_entryText.length > 0)
            [_entryText deleteCharactersInRange:NSMakeRange(_entryText.length - 1, 1)];
    } else if ([k isEqualToString:@"hours"])   { [_entryText appendString:@"h"]; }
    else if   ([k isEqualToString:@"minutes"]) { [_entryText appendString:@"m"]; }
    else if   ([k isEqualToString:@"seconds"]) { [_entryText appendString:@"s"]; }
    else { [_entryText appendString:k]; }                    // digit, '.', or ':'
    [self refreshEntryDisplay];
}

- (void)refreshEntryDisplay {
    _entryDisplay.text = (_entryText.length > 0) ? _entryText : @"0";
}

- (void)keypadCancel { [self hideKeypad]; }

- (void)keypadDone {
    int secs = [self parseEntryToSeconds:_entryText];
    if (secs < 0) secs = 0;
    if (_keypadKind == 1) {                              // count-down: set the duration
        if (secs > CD_MAX_MIN * 60) secs = CD_MAX_MIN * 60;
        _cdSetSec[_keypadIndex]   = secs;
        _cdRemaining[_keypadIndex] = secs;
        [self refreshCountdown:_keypadIndex];
        [self updatePulse];
    } else {                                             // count-up: set the elapsed start
        int cap = 99 * 3600 + 59 * 60 + 59;
        if (secs > cap) secs = cap;
        _swSeconds[_keypadIndex] = secs;
        [self refreshStopwatch:_keypadIndex];
    }
    [self hideKeypad];
}

// Turn free-form text into seconds. Accepts:
//   colon form  "1:30:00" (h:m:s), "1:30" (m:s)
//   unit form   "90s", "1.5h", "1h30m"  (decimals ok)
//   bare number "5", "1.5"  -> assumed MINUTES  (so 1.5 -> 1:30)
- (int)parseEntryToSeconds:(NSString *)raw {
    NSString *s = [[raw stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
    if (s.length == 0) return 0;

    if ([s rangeOfString:@":"].location != NSNotFound) {     // colon form, right-aligned
        NSArray *p = [s componentsSeparatedByString:@":"];
        NSUInteger n = p.count;
        double h = 0, m = 0, sec = 0;
        if (n >= 1) sec = [p[n - 1] doubleValue];
        if (n >= 2) m   = [p[n - 2] doubleValue];
        if (n >= 3) h   = [p[n - 3] doubleValue];
        return (int)llround(h * 3600 + m * 60 + sec);
    }

    BOOL hasUnit = ([s rangeOfString:@"h"].location != NSNotFound ||
                    [s rangeOfString:@"m"].location != NSNotFound ||
                    [s rangeOfString:@"s"].location != NSNotFound);
    if (hasUnit) {                                            // unit form
        double total = 0;
        NSScanner *sc = [NSScanner scannerWithString:s];
        while (![sc isAtEnd]) {
            double num = 0;
            if (![sc scanDouble:&num]) { sc.scanLocation = sc.scanLocation + 1; continue; }
            double factor = 60;   // a number with no unit here defaults to minutes
            NSUInteger loc = sc.scanLocation;
            if (loc < s.length) {
                unichar c = [s characterAtIndex:loc];
                if (c == 'h')      { factor = 3600; sc.scanLocation = loc + 1; }
                else if (c == 'm') { factor = 60;   sc.scanLocation = loc + 1; }
                else if (c == 's') { factor = 1;    sc.scanLocation = loc + 1; }
            }
            total += num * factor;
        }
        return (int)llround(total);
    }

    return (int)llround([s doubleValue] * 60);               // bare number -> minutes
}

@end
