/*
 * Little16 - iPhone X gestures for iOS 16
 * Target: iPhone 8/8 Plus, iOS 16.x, Dopamine (rootless)
 *
 * Features:
 *  - Home indicator bar at bottom (like iPhone X)
 *  - Swipe-up-to-home gesture
 *  - Floating dock with recents
 *  - iPhone X icon grid layout (optional)
 *
 * Bugs fixed:
 *  [1] Landscape home-gesture animation: app thu nhỏ sai vị trí rồi snap
 *      Root cause: presentingEdge trả về side-edge trong landscape
 *  [2] Bar flash 0.3s khi re-enter app landscape
 *      Root cause: SBFloatingDockView/SBFHomeGrabberView hiện instant
 *      trong app-launch transition trước khi bị hide bởi app
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ═══════════════════════════════════════════════════════════════════════════
// Private headers
// ═══════════════════════════════════════════════════════════════════════════

@interface SBHomeGestureSettings : NSObject
- (BOOL)isHomeGestureEnabled;
- (void)setHomeGestureEnabled:(BOOL)enabled;
@end

@interface SBFHomeGrabberSettings : NSObject
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)enabled;
@end

@interface SBFloatingDockController : UIViewController
- (BOOL)isFloatingDockSupported;
- (long long)presentingEdge;
- (void)setPresentingEdge:(long long)edge;
@end

@interface SBFloatingDockDefaults : NSObject
- (BOOL)recentsEnabled;
- (void)setRecentsEnabled:(BOOL)enabled;
- (BOOL)appLibraryEnabled;
- (void)setAppLibraryEnabled:(BOOL)enabled;
- (NSInteger)maxSuggestions;
@end

@interface SBIconListGridLayoutConfiguration : NSObject
- (NSUInteger)numberOfPortraitColumns;
- (NSUInteger)numberOfPortraitRows;
- (void)setNumberOfPortraitColumns:(NSUInteger)cols;
- (void)setNumberOfPortraitRows:(NSUInteger)rows;
@end

@interface SBIconLocationDock : NSObject
@end

@interface SBFloatingDockSuggestionsModel : NSObject
- (NSInteger)maxSuggestions;
- (BOOL)recentsEnabled;
- (BOOL)isHandoff;
@end

@interface SBFloatingDockSuggestionsViewController : UIViewController
@end

// Home grabber / indicator view (the pill bar at the bottom)
@interface SBFHomeGrabberView : UIView
- (void)setAlpha:(CGFloat)alpha;
@end

// Floating dock view
@interface SBFloatingDockView : UIView
- (void)setAlpha:(CGFloat)alpha;
@end

// App launch / dismiss transition context
@interface SBMainWorkspace : NSObject
+ (instancetype)sharedInstance;
@end

// Control Center quick-action buttons (camera / flashlight on lock screen)
@interface CSQuickActionsView : UIView
- (BOOL)wantsQuickActions;
@end

@interface CSQuickActionsViewController : UIViewController
- (BOOL)wantsQuickActions;
- (BOOL)hasCamera;
- (BOOL)hasFlashlight;
@end

// ═══════════════════════════════════════════════════════════════════════════
// Helper
// ═══════════════════════════════════════════════════════════════════════════

static BOOL isIPad(void) {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
}

// iPhone X and newer natively have these features — don't double-hook them
static BOOL isModernIPhone(void) {
    // iPhone X/XS/XR/11/12/13/14/15 have notch or Dynamic Island → safe area top > 20
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) return NO;
    CGFloat topInset = w.safeAreaInsets.top;
    return topInset > 25.0; // notch devices: ~44pt, home-button: 20pt status bar only
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. Home Gesture — enable swipe-up-to-home on iPhone 8/8 Plus
// ═══════════════════════════════════════════════════════════════════════════

%hook SBHomeGestureSettings

- (BOOL)isHomeGestureEnabled {
    if (isModernIPhone() || isIPad()) return %orig;
    return YES;
}

%end


// ═══════════════════════════════════════════════════════════════════════════
// 2. Home Indicator (grabber bar at bottom)
// ═══════════════════════════════════════════════════════════════════════════

%hook SBFHomeGrabberSettings

- (BOOL)isEnabled {
    if (isModernIPhone() || isIPad()) return %orig;
    return YES;
}

%end


// ═══════════════════════════════════════════════════════════════════════════
// 3. Floating Dock
//    + FIX: presentingEdge always returns bottom to prevent landscape
//           animation glitch where app shrinks to wrong position then snaps
// ═══════════════════════════════════════════════════════════════════════════

%hook SBFloatingDockController

- (BOOL)isFloatingDockSupported {
    if (isModernIPhone() || isIPad()) return %orig;
    return YES;
}

/*
 * FIX — landscape animation bug
 *
 * On non-X iPhones with Little16, in landscape mode the dock's presentingEdge
 * is left/right instead of bottom. SpringBoard uses this edge to compute the
 * destination rect for the "minimize to home" animation. With a wrong edge:
 *  1. App shrinks toward a side/top point   (visually wrong)
 *  2. ~1s later snaps to actual dock icon   (the "jump" you see)
 *
 * Fix: always report bottom edge (3) so the animation target is computed
 * correctly regardless of device orientation.
 *
 * Edge constants (UIRectEdge / SBEdge):
 *   0 = top, 1 = left, 2 = right, 3 = bottom
 */
- (long long)presentingEdge {
    return 3; // kEdgeBottom — always
}

/*
 * FIX part 2 — force dock frame sync after rotation
 *
 * Even with the correct edge, the dock's _floatingDockView frame may still
 * be stale (portrait coordinates) when the animation begins. Force a layout
 * pass so the frame reflects the current orientation before SpringBoard
 * starts computing the shrink-to-icon animation.
 */
- (void)viewDidLayoutSubviews {
    %orig;

    UIView *dockView = nil;
    @try { dockView = [self valueForKey:@"_floatingDockView"]; } @catch (...) {}
    if (!dockView) {
        @try { dockView = [self valueForKey:@"floatingDockView"]; } @catch (...) {}
    }

    if (dockView) {
        UIInterfaceOrientation orient =
            [UIApplication sharedApplication].statusBarOrientation;
        if (UIInterfaceOrientationIsLandscape(orient)) {
            [dockView setNeedsLayout];
            [dockView layoutIfNeeded];
        }
    }
}

%end


// ═══════════════════════════════════════════════════════════════════════════
// 4. Floating Dock Defaults — enable recents in dock like iPhone X
// ═══════════════════════════════════════════════════════════════════════════

%hook SBFloatingDockDefaults

- (BOOL)recentsEnabled {
    if (isIPad()) return %orig;
    return YES;
}

- (BOOL)appLibraryEnabled {
    if (isIPad()) return %orig;
    return YES;
}

%end


// ═══════════════════════════════════════════════════════════════════════════
// 5. Dock Suggestions Model — allow recent app suggestions in dock
// ═══════════════════════════════════════════════════════════════════════════

%hook SBFloatingDockSuggestionsModel

- (BOOL)recentsEnabled {
    return YES;
}

- (BOOL)isHandoff {
    return %orig; // keep original handoff behaviour
}

%end


// ═══════════════════════════════════════════════════════════════════════════
// 6. Icon Grid Layout — 4 cols × 6 rows (iPhone X style) on 8 Plus
//    Comment this section out if you prefer keeping the original 4×5 grid
// ═══════════════════════════════════════════════════════════════════════════

%hook SBIconListGridLayoutConfiguration

- (NSUInteger)numberOfPortraitColumns {
    if (isIPad() || isModernIPhone()) return %orig;
    // iPhone 8 Plus (5.5") → keep 4 columns like stock
    return %orig;
}

- (NSUInteger)numberOfPortraitRows {
    if (isIPad() || isModernIPhone()) return %orig;
    // Uncomment to add an extra row like iPhone X (5 → 6):
    // return %orig + 1;
    return %orig;
}

%end


// ═══════════════════════════════════════════════════════════════════════════
// 7. Control Center Quick Actions (Camera / Flashlight buttons on lock screen)
//    iPhone X shows these; enable on 8 Plus too
// ═══════════════════════════════════════════════════════════════════════════

%hook CSQuickActionsViewController

- (BOOL)wantsQuickActions {
    return YES;
}

- (BOOL)hasCamera {
    return YES;
}

- (BOOL)hasFlashlight {
    return YES;
}

%end

%hook CSQuickActionsView

- (BOOL)wantsQuickActions {
    return YES;
}

%end


// ═══════════════════════════════════════════════════════════════════════════
// 8. UIWindow — fix residual landscape orientation desync
//    After screen rotates, trigger a layout pass on the dock so its frame
//    is always correct before the next home gesture.
// ═══════════════════════════════════════════════════════════════════════════

%hook UIWindow

- (void)_setRotatableViewOrientation:(long long)orientation
                            duration:(double)duration
                               force:(BOOL)force {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene respondsToSelector:@selector(floatingDockController)]) {
                id ctrl = [scene performSelector:@selector(floatingDockController)];
                if ([ctrl respondsToSelector:@selector(view)]) {
                    UIView *v = [ctrl view];
                    [v setNeedsLayout];
                    [v layoutIfNeeded];
                }
            }
        }
    });
}

%end


// ═══════════════════════════════════════════════════════════════════════════
// 9. FIX — Bar flash ~0.3s khi re-enter app landscape
//
// Vấn đề: khi mở lại app đang ở landscape, SpringBoard briefly hiện
// floating dock + home indicator (vì ở home screen chúng đang visible),
// sau đó app yêu cầu hide chúng → người dùng thấy flash ~0.3s.
//
// Root cause: visibility transition xảy ra AFTER app window đã present,
// tức là dock/bar briefly overlap lên app content rồi mới fade out.
//
// Fix: override setAlpha: trên SBFHomeGrabberView và SBFloatingDockView
// để khi chúng bị set alpha = 0 (hide), dùng animation ngắn thay vì
// instant; và khi được set alpha = 1 (show), chỉ show nếu không đang
// trong app-launch transition.
//
// Cách detect transition: theo dõi flag qua SBMainWorkspace notification.
// ═══════════════════════════════════════════════════════════════════════════

// Flag: đang trong app-launch / app-dismiss transition
static BOOL gInAppTransition = NO;
// Duration cho fade-out animation của bar khi app launch
static const NSTimeInterval kBarFadeOutDuration = 0.15;

// ── Notification-based transition tracking ────────────────────────────────
// SpringBoard post các notification khi app launch/dismiss transition bắt đầu/kết thúc

static void setupTransitionObserver(void) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    // App về foreground → transition bắt đầu → mark flag
    [nc addObserverForName:@"SBMainWorkspaceDidBeginLaunchingApplicationNotification"
                   object:nil queue:nil usingBlock:^(NSNotification *note) {
        gInAppTransition = YES;
        // Auto-reset sau 0.5s phòng transition không post end notification
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            gInAppTransition = NO;
        });
    }];

    // Transition kết thúc → reset flag
    [nc addObserverForName:@"SBMainWorkspaceDidFinishLaunchingApplicationNotification"
                   object:nil queue:nil usingBlock:^(NSNotification *note) {
        gInAppTransition = NO;
    }];

    // App về background / home → transition
    [nc addObserverForName:@"SBMainWorkspaceWillBeginDismissingApplicationNotification"
                   object:nil queue:nil usingBlock:^(NSNotification *note) {
        gInAppTransition = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            gInAppTransition = NO;
        });
    }];
}

// ── Home grabber (pill bar) flash fix ─────────────────────────────────────

%hook SBFHomeGrabberView

- (void)setAlpha:(CGFloat)alpha {
    // Khi đang trong app-launch transition và bar bị request hiện (alpha=1):
    // skip instant show, để nó remain hidden cho tới khi transition xong.
    if (gInAppTransition && alpha > 0.5) {
        // Không set alpha = 1 ngay — schedule sau transition
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!gInAppTransition) {
                %orig(alpha); // chỉ show nếu đã về home
            }
        });
        return;
    }
    // Khi bar bị hide (alpha → 0): dùng fade animation ngắn thay vì instant
    if (alpha < 0.1 && self.alpha > 0.5) {
        [UIView animateWithDuration:kBarFadeOutDuration animations:^{
            %orig(alpha);
        }];
        return;
    }
    %orig;
}

%end

// ── Floating dock flash fix ───────────────────────────────────────────────

%hook SBFloatingDockView

- (void)setAlpha:(CGFloat)alpha {
    // Same logic: suppress instant-show during app-launch transition
    if (gInAppTransition && alpha > 0.5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!gInAppTransition) {
                %orig(alpha);
            }
        });
        return;
    }
    if (alpha < 0.1 && self.alpha > 0.5) {
        [UIView animateWithDuration:kBarFadeOutDuration animations:^{
            %orig(alpha);
        }];
        return;
    }
    %orig;
}

%end


// ═══════════════════════════════════════════════════════════════════════════
// Constructor
// ═══════════════════════════════════════════════════════════════════════════

%ctor {
    // Only inject into SpringBoard
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

    %init;
    setupTransitionObserver();
    NSLog(@"[Little16] Loaded — iOS 16 iPhone X gestures + landscape fix + bar flash fix");
}
