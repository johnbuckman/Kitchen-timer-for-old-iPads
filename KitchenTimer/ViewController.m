#import "ViewController.h"
#import <AudioToolbox/AudioToolbox.h>

#define NCOUNT 2          // 2 stopwatches, 2 countdown timers -> 2x2 grid
#define CD_MAX_MIN 180    // cap a countdown at 180 minutes
#define DING_SOUND 1005   // "nice ding" alert tone (try 1013 / 1057 'Tink' to taste)
#define DING_EVERY 5      // re-ding every N seconds while in overtime
#define SCRUB_PTS_PER_MIN 7.0  // vertical points of drag per minute (smaller = faster)

@interface ViewController () <UIGestureRecognizerDelegate>
{
    NSTimer *_master;            // single 1s tick driving everything
    NSDateFormatter *_clockFmt;

    UILabel *_clock;

    // Stopwatches (count UP, displayed in whole minutes)
    int      _swSeconds[NCOUNT];
    BOOL     _swRunning[NCOUNT];
    UILabel *_swValue[NCOUNT];
    UIButton *_swToggle[NCOUNT];
    UIButton *_swReset[NCOUNT];

    // Countdown timers (count DOWN, set + displayed in whole minutes)
    int      _cdRemaining[NCOUNT]; // seconds
    int      _cdSetMin[NCOUNT];    // minutes the user dialed in
    BOOL     _cdRunning[NCOUNT];
    UILabel *_cdValue[NCOUNT];
    UIButton *_cdToggle[NCOUNT];
    UIButton *_cdReset[NCOUNT];

    // Drag-to-scrub state (tap-hold-slide on a countdown card)
    CGFloat  _dragStartY[NCOUNT];
    int      _dragStartMin[NCOUNT];

    BOOL _pulsing;   // YES while the overtime black<->white flash is running
}
@end

@implementation ViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _clockFmt = [[NSDateFormatter alloc] init];
    _clockFmt.dateFormat = @"H:mm";

    for (int i = 0; i < NCOUNT; i++) {
        _cdSetMin[i] = 5;
        _cdRemaining[i] = _cdSetMin[i] * 60;
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

#pragma mark - UI construction

- (void)buildUI {
    UIStackView *root = [[UIStackView alloc] init];
    root.axis = UILayoutConstraintAxisVertical;
    root.alignment = UIStackViewAlignmentFill;
    root.distribution = UIStackViewDistributionFill;
    root.spacing = 18;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
        [root.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
        [root.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:24],
        [root.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-24],
    ]];

    // --- Clock in a dark "pill" so it stays readable while the background pulses ---
    _clock = [[UILabel alloc] init];
    _clock.font = [UIFont monospacedDigitSystemFontOfSize:108 weight:UIFontWeightBold];
    _clock.textColor = [UIColor whiteColor];
    _clock.textAlignment = NSTextAlignmentCenter;
    _clock.text = @"--:--:--";
    _clock.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *pill = [[UIView alloc] init];
    pill.backgroundColor = [UIColor blackColor];   // invisible on the black bg; a black pill during the white pulse
    pill.layer.cornerRadius = 70;   // == half the pill height -> stadium/pill shape
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    [pill addSubview:_clock];

    UIView *clockRow = [[UIView alloc] init];   // full-width row that centers the pill
    [clockRow addSubview:pill];
    [clockRow setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

    [NSLayoutConstraint activateConstraints:@[
        [pill.heightAnchor constraintEqualToConstant:140],
        [pill.centerXAnchor constraintEqualToAnchor:clockRow.centerXAnchor],
        [pill.topAnchor constraintEqualToAnchor:clockRow.topAnchor],
        [pill.bottomAnchor constraintEqualToAnchor:clockRow.bottomAnchor],
        [pill.leadingAnchor constraintGreaterThanOrEqualToAnchor:clockRow.leadingAnchor],
        [pill.trailingAnchor constraintLessThanOrEqualToAnchor:clockRow.trailingAnchor],
        [_clock.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:44],
        [_clock.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-44],
        [_clock.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
    ]];
    [root addArrangedSubview:clockRow];

    // --- 2x2 grid that fills the remaining space ---
    UIStackView *topRow = [self gridRow:@[ [self stopwatchCard:0], [self stopwatchCard:1] ]];
    UIStackView *botRow = [self gridRow:@[ [self countdownCard:0], [self countdownCard:1] ]];

    UIStackView *grid = [[UIStackView alloc] initWithArrangedSubviews:@[ topRow, botRow ]];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.distribution = UIStackViewDistributionFillEqually;
    grid.spacing = 18;
    [grid setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [root addArrangedSubview:grid];
}

- (UIStackView *)gridRow:(NSArray *)cards {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:cards];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 18;
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

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self cardTitle:[NSString stringWithFormat:@"Count up #%d", i + 1]],
        _swValue[i],
        [self buttonRow:@[ _swToggle[i], _swReset[i] ]] ]];
    content.axis = UILayoutConstraintAxisVertical;
    content.alignment = UIStackViewAlignmentFill;
    content.distribution = UIStackViewDistributionFill;
    content.spacing = 14;
    return [self cardContainer:content];
}

- (UIView *)countdownCard:(int)i {
    _cdValue[i] = [self bigValueLabel];

    UIButton *minus = [self bigButton:@"–" color:[self grayColor] action:@selector(cdMinus:) tag:i fontSize:42];
    UIButton *plus  = [self bigButton:@"+" color:[self grayColor] action:@selector(cdPlus:) tag:i fontSize:42];
    [minus.widthAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
    [plus.widthAnchor constraintGreaterThanOrEqualToConstant:72].active = YES;
    [minus setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [plus setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *setRow = [[UIStackView alloc] initWithArrangedSubviews:@[ minus, _cdValue[i], plus ]];
    setRow.axis = UILayoutConstraintAxisHorizontal;
    setRow.alignment = UIStackViewAlignmentCenter;   // keep -/+ a sane size; let the number be big
    setRow.distribution = UIStackViewDistributionFill;
    setRow.spacing = 14;
    [setRow setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];

    _cdToggle[i] = [self bigButton:@"Down"
                             color:[self blueColor] action:@selector(cdToggle:) tag:i fontSize:26];
    _cdReset[i] = [self bigButton:@"Reset"
                            color:[self grayColor] action:@selector(cdReset:) tag:i fontSize:26];

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self cardTitle:[NSString stringWithFormat:@"Count down #%d", i + 1]],
        setRow,
        [self buttonRow:@[ _cdToggle[i], _cdReset[i] ]] ]];
    content.axis = UILayoutConstraintAxisVertical;
    content.alignment = UIStackViewAlignmentFill;
    content.distribution = UIStackViewDistributionFill;
    content.spacing = 14;

    UIView *card = [self cardContainer:content];
    card.tag = i;
    // Tap-and-hold anywhere on the card body, then slide vertically to scrub minutes fast.
    UILongPressGestureRecognizer *scrub =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(cdScrub:)];
    scrub.minimumPressDuration = 0.2;
    scrub.delegate = self;   // ignore touches that start on the +/- / Start / Reset buttons
    [card addGestureRecognizer:scrub];
    return card;
}

// Don't let the scrub gesture start on top of a button — buttons keep their normal taps.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIControl class]];
}

- (void)cdScrub:(UILongPressGestureRecognizer *)g {
    int i = (int)g.view.tag;
    if (_cdRunning[i]) return;   // only adjust a stopped timer, same as the +/- buttons
    CGPoint p = [g locationInView:g.view];
    if (g.state == UIGestureRecognizerStateBegan) {
        _dragStartY[i] = p.y;
        _dragStartMin[i] = _cdSetMin[i];
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGFloat dy = _dragStartY[i] - p.y;            // slide up = increase
        int m = _dragStartMin[i] + (int)(dy / SCRUB_PTS_PER_MIN);
        if (m < 0) m = 0;
        if (m > CD_MAX_MIN) m = CD_MAX_MIN;
        if (m != _cdSetMin[i]) {
            _cdSetMin[i] = m;
            _cdRemaining[i] = m * 60;
            [self refreshCountdown:i];
        }
    }
}

#pragma mark - Colors

- (UIColor *)greenColor { return [UIColor colorWithRed:0.20 green:0.55 blue:0.30 alpha:1.0]; }
- (UIColor *)redColor   { return [UIColor colorWithRed:0.70 green:0.25 blue:0.20 alpha:1.0]; }
- (UIColor *)blueColor  { return [UIColor colorWithRed:0.20 green:0.45 blue:0.70 alpha:1.0]; }
- (UIColor *)grayColor  { return [UIColor colorWithWhite:0.32 alpha:1.0]; }
- (UIColor *)orangeColor{ return [UIColor colorWithRed:1.0 green:0.55 blue:0.0 alpha:1.0]; }

#pragma mark - Tick

- (void)tick {
    _clock.text = [_clockFmt stringFromDate:[NSDate date]];

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
}

#pragma mark - Stopwatch actions

- (void)swToggle:(UIButton *)b {
    int i = (int)b.tag;
    _swRunning[i] = !_swRunning[i];
    [b setTitle:(_swRunning[i] ? @"Stop" : @"Up") forState:UIControlStateNormal];
    b.backgroundColor = _swRunning[i] ? [self redColor] : [self greenColor];
    [self refreshStopwatch:i];   // show/hide Reset right away
}

- (void)swReset:(UIButton *)b {
    int i = (int)b.tag;
    _swRunning[i] = NO;
    _swSeconds[i] = 0;
    [_swToggle[i] setTitle:@"Up" forState:UIControlStateNormal];
    _swToggle[i].backgroundColor = [self greenColor];
    [self refreshStopwatch:i];
}

#pragma mark - Countdown actions

- (void)cdPlus:(UIButton *)b {
    int i = (int)b.tag;
    if (_cdRunning[i]) return;
    if (_cdSetMin[i] < CD_MAX_MIN) _cdSetMin[i]++;
    _cdRemaining[i] = _cdSetMin[i] * 60;
    [self refreshCountdown:i];
}

- (void)cdMinus:(UIButton *)b {
    int i = (int)b.tag;
    if (_cdRunning[i]) return;
    if (_cdSetMin[i] > 0) _cdSetMin[i]--;
    _cdRemaining[i] = _cdSetMin[i] * 60;
    [self refreshCountdown:i];
}

- (void)cdToggle:(UIButton *)b {
    int i = (int)b.tag;
    if (!_cdRunning[i]) {
        if (_cdRemaining[i] <= 0) _cdRemaining[i] = _cdSetMin[i] * 60;
        if (_cdRemaining[i] <= 0) return;
        _cdRunning[i] = YES;
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
    _cdRunning[i] = NO;
    _cdRemaining[i] = _cdSetMin[i] * 60;
    [_cdToggle[i] setTitle:@"Down" forState:UIControlStateNormal];
    _cdToggle[i].backgroundColor = [self blueColor];
    [self refreshCountdown:i];
    [self updatePulse];   // reset clears overtime -> end the flash
}

#pragma mark - Display

- (void)refreshAll {
    for (int i = 0; i < NCOUNT; i++) { [self refreshStopwatch:i]; [self refreshCountdown:i]; }
}

// Whole minutes:seconds, no hours. Handles negative (overtime) values, e.g. "-0:07".
- (NSString *)mmss:(int)totalSeconds {
    NSString *sign = (totalSeconds < 0) ? @"-" : @"";
    int s = (totalSeconds < 0) ? -totalSeconds : totalSeconds;
    return [NSString stringWithFormat:@"%@%d:%02d", sign, s / 60, s % 60];
}

- (void)refreshStopwatch:(int)i {
    _swValue[i].text = [self mmss:_swSeconds[i]];
    // Reset only matters once it's running or has counted something.
    _swReset[i].hidden = (!_swRunning[i] && _swSeconds[i] == 0);
}

- (void)refreshCountdown:(int)i {
    _cdValue[i].text = [self mmss:_cdRemaining[i]];
    // Orange once at/under zero so the overtime number stays readable on the grey card
    // regardless of the pulsing background behind it.
    _cdValue[i].textColor = (_cdRemaining[i] <= 0) ? [self orangeColor] : [UIColor whiteColor];
    // Reset only matters once it's running or no longer at its freshly-set value.
    _cdReset[i].hidden = (!_cdRunning[i] && _cdRemaining[i] == _cdSetMin[i] * 60);
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

@end
