#import "AppDelegate.h"
#import "ViewController.h"

// Build a fresh full-screen window holding the timer view controller.
static UIWindow *MakeTimerWindow(UIWindow *window) {
    window.rootViewController = [[ViewController alloc] init];
    window.backgroundColor = [UIColor blackColor];
    [window makeKeyAndVisible];
    return window;
}

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Keep the screen awake — this is a kitchen timer meant to sit on a counter.
    [UIApplication sharedApplication].idleTimerDisabled = YES;

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 13.0, *)) {
        // Modern iOS: the window is created by SceneDelegate (below) so it tracks the
        // window scene's size/orientation correctly. Nothing to do here.
        return YES;
    }
#endif
    // iOS 9–12 (incl. the armv7 jailbreak build): classic single window.
    self.window = MakeTimerWindow([[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]]);
    return YES;
}

@end

// --- Modern scene lifecycle (iOS 13+). Compiled out on the old iOS 9 SDK. -----------
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000

API_AVAILABLE(ios(13.0))
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation SceneDelegate
- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions API_AVAILABLE(ios(13.0)) {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = MakeTimerWindow([[UIWindow alloc] initWithWindowScene:windowScene]);
}
@end

#endif
