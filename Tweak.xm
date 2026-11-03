/*
 * Little16 — iPad-style floating dock + gestures on iPhone (iOS 16, rootless)
 *
 * Faithful reconstruction of the original Little16 0.0.9 (michaelmelita1),
 * decoded from the shipped arm64 dylib's hook table. The original does NOT
 * force the home grabber on; it turns iPhone into "iPad mode" for dock/home
 * gesture/control center and keeps the grabber disabled.
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ─── private interfaces ──────────────────────────────────────────────────────

@interface CSQuickActionsButton : UIView
@end

@interface CSQuickActionsView : UIView
- (UIEdgeInsets)_buttonOutsets;
- (UIView *)flashlightButton;
- (UIView *)cameraButton;
@end

@interface SBFloatingDockSuggestionsModel : NSObject
- (id)currentAppSuggestion;
@end

@interface SBIconListView : UIView
- (id)iconLocation;
@end

@interface SBIconListGridLayoutConfiguration : NSObject
- (NSUInteger)numberOfPortraitRows;
@end

@interface NSObject (L16Private)
- (BOOL)isHandoff;
@end

@interface SBFloatingDockRootViewController : UIViewController
@end

@interface SBFloatingDockController : NSObject
- (BOOL)isFloatingDockPresented;
@end

// ─── helpers ─────────────────────────────────────────────────────────────────

static BOOL L16ViewContainsClass(UIView *view, Class cls, int depth) {
    if (!view || depth > 20) return NO;
    if ([view isKindOfClass:cls]) return YES;
    for (UIView *sub in [view subviews]) {
        if (L16ViewContainsClass(sub, cls, depth + 1)) return YES;
    }
    return NO;
}

// ─── UIWindow: fake bottom safe-area (20pt) when lock-screen quick action
//     buttons are in the window, so they sit like on iPhone X ───────────────

%hook UIWindow
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = %orig;
    if (!(insets.bottom > 0)) {
        Class btn = NSClassFromString(@"CSQuickActionsButton");
        if (btn && L16ViewContainsClass(self, btn, 0)) insets.bottom = 20.0;
    }
    return insets;
}
%end

// ─── Lock screen camera / flashlight buttons ─────────────────────────────────

%hook CSQuickActionsView
- (BOOL)wantsQuickActions { return YES; }
- (BOOL)_prototypingAllowsButtons { return YES; }
- (void)_layoutQuickActionButtons {
    CGRect b = [[UIScreen mainScreen] bounds];
    UIEdgeInsets o = [self _buttonOutsets];
    CGFloat y = b.size.height - 90.0 - o.top;
    [[self flashlightButton] setFrame:CGRectMake(46.0, y, 50.0, 50.0)];
    [[self cameraButton] setFrame:CGRectMake(b.size.width - 96.0, y, 50.0, 50.0)];
}
%end

%hook CSQuickActionsViewController
+ (BOOL)deviceSupportsButtons { return YES; }
- (BOOL)hasCamera { return YES; }
- (BOOL)hasFlashlight { return YES; }
%end

// ─── Floating dock (iPad style) ──────────────────────────────────────────────

%hook SBFloatingDockController
+ (BOOL)isFloatingDockSupported { return YES; }
- (void)_configureFloatingDockBehaviorAssertionForOpenFolder:(id)folder atLevel:(long long)level {
    // original: no-op
}
%end

%hook SBFloatingDockDefaults
- (void)setRecentsEnabled:(BOOL)enabled { %orig(YES); }
- (BOOL)recentsEnabled { return YES; }
- (void)setAppLibraryEnabled:(BOOL)enabled { %orig(NO); }
- (BOOL)appLibraryEnabled { return NO; }
%end

%hook SBIconListGridLayoutConfiguration
- (NSUInteger)numberOfPortraitColumns {
    NSUInteger c = %orig;
    (void)[self numberOfPortraitRows];
    return c;
}
%end

%hook SBIconListView
- (NSUInteger)maximumIconCount {
    if ([[self iconLocation] isEqual:@"SBIconLocationDock"]) return 4;
    return %orig;
}
%end

%hook SBFloatingDockSuggestionsModel
- (BOOL)recentDisplayItemsController:(id)controller shouldAddItem:(id)item {
    if ([[self currentAppSuggestion] isHandoff]) return NO;
    return %orig;
}
- (id)initWithMaximumNumberOfSuggestions:(NSUInteger)max
                          iconController:(id)a
                        recentsController:(id)b
                          recentsDataStore:(id)c
                          recentsDefaults:(id)d
                     floatingDockDefaults:(id)e
                     appSuggestionManager:(id)f
                    applicationController:(id)g {
    return %orig(3, a, b, c, d, e, f, g);
}
- (NSUInteger)maxSuggestions { return 3; }
%end

%hook SBFloatingDockSuggestionsViewController
- (id)initWithNumberOfRecents:(NSUInteger)n
               iconController:(id)a
        applicationController:(id)b
layoutStateTransitionCoordinator:(id)c
             suggestionsModel:(id)d
             iconViewProvider:(id)e {
    return %orig(3, a, b, c, d, e);
}
%end

// ─── Home gesture / Control Center ───────────────────────────────────────────

%hook SBHomeGestureSettings
- (BOOL)isHomeGestureEnabled { return YES; }
%end

%hook CCSControlCenterDefaults
- (long long)_defaultPresentationGesture { return 1; }
%end

%hook SBControlCenterController
- (unsigned long long)presentingEdge { return 1; } // top
%end

// original keeps the grabber disabled
%hook SBFHomeGrabberSettings
- (BOOL)isEnabled { return NO; }
- (void)setEnabled:(BOOL)enabled { %orig(NO); }
%end

// ─── Status bar: iPad forced-cellular provider ───────────────────────────────

%hook _UIStatusBarVisualProvider_iOS
+ (Class)class {
    return NSClassFromString(@"_UIStatusBarVisualProvider_Pad_ForcedCellular");
}
%end

// ─── Notification list position (iOS 16+) ────────────────────────────────────

%hook NCNotificationListView
- (void)setFrame:(CGRect)frame {
    NSOperatingSystemVersion v = {16, 0, 0};
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:v]) {
        frame.origin.x = 0;
        frame.origin.y = -100.0;
    }
    %orig(frame);
}
%end

%hook CSFullscreenNotificationView
- (void)setFrame:(CGRect)frame {
    frame.origin.x = 0;
    frame.origin.y = -50.0;
    %orig(frame);
}
%end



// ─── TRACE + experiment switches (v1.0.3) ────────────────────────────────────
// Trace file : /var/mobile/Library/Little16-trace.txt  (reset on every respring)
// Switch file: /var/mobile/Library/Little16-flags.txt   (plain text, words below;
//              re-read every ~1s, no respring needed)
//   nodelay  -> zero the zoom delays of SBCenterAppIconZoomAnimator
//   nodipfix / noiconfilter -> turn OFF the dock-dip fix / the landscape icon-target fix
//   nohidedock -> turn OFF the dock flash fix (hide dock window while entering an app)

@interface SBHomeGestureFinalDestinationSwitcherModifier : NSObject
- (long long)currentFinalDestination;
- (id)finalDestinationReason;
@end

static long long L16Orient(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(activeInterfaceOrientation)])
        return ((long long (*)(id, SEL))objc_msgSend)(app, @selector(activeInterfaceOrientation));
    return (long long)[app statusBarOrientation];
}

static BOOL L16Flag(NSString *name) {
    static NSString *cache = nil;
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!cache || now - last > 1.0) {
        cache = [NSString stringWithContentsOfFile:@"/var/mobile/Library/Little16-flags.txt"
                                          encoding:NSUTF8StringEncoding error:nil] ?: @"";
        last = now;
    }
    return [cache containsString:name];
}

static void L16Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static void L16Log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%.3f o=%lld %@\n", CACurrentMediaTime(), L16Orient(), m];
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("little16.trace", DISPATCH_QUEUE_SERIAL);
        [@"" writeToFile:@"/var/mobile/Library/Little16-trace.txt" atomically:YES
                encoding:NSUTF8StringEncoding error:nil];
    });
    dispatch_async(q, ^{
        FILE *f = fopen("/var/mobile/Library/Little16-trace.txt", "a");
        if (f) { fputs([line UTF8String], f); fclose(f); }
    });
}

static NSUInteger gL16Gen = 0;
static CFTimeInterval gL16StayEnd = 0;      // last gesture end that kept the app (dest 0)
static CFTimeInterval gL16PresentSeen = 0;  // last _presentFloatingDockIfDismissed call
static int gL16SwitcherLookup = 0;          // >0 while the switcher resolves an icon target


// Bug A fix (confirmed by trace): when entering an app (env mode 3) the system keeps
// the dock "visible" (to=1) and then slides it away over ~0.75s while the app is
// already on screen -> visible flash. Hide the dock window for that transition and
// show it again once the slide-away has finished. Disable with flag "nohidedock".
static BOOL gL16Hidden = NO;

static void L16RestoreDock(UIWindow *w) {
    if (gL16Hidden && w) { w.alpha = 1.0; gL16Hidden = NO; }
}

%hook SBFloatingDockRootViewController
- (void)prepareForTransitionToEnvironmentMode:(long long)mode
                              fromDockVisible:(BOOL)from
                                toDockVisible:(BOOL)to {
    %orig;
    L16Log(@"DOCK prepareTransition mode=%lld from=%d to=%d", mode, from, to);
    gL16Gen++;
    if (mode == 3 && !L16Flag(@"nohidedock")) {
        UIWindow *w = [[self view] window];
        if (w) {
            w.alpha = 0.0; gL16Hidden = YES;
            NSUInteger g = gL16Gen;
            __weak UIWindow *ww = w;
            // safety net: never leave the dock hidden
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ if (g == gL16Gen) L16RestoreDock(ww); });
        }
    }
}
- (void)cleanupAfterTransitionToEnvironmentMode:(long long)mode {
    %orig;
    L16Log(@"DOCK cleanupTransition mode=%lld", mode);
}
- (void)_setPresentedProgress:(double)progress animated:(BOOL)animated
                  interactive:(BOOL)interactive completion:(id)completion {
    L16Log(@"DOCK setPresentedProgress %.2f anim=%d inter=%d", progress, animated, interactive);
    if (progress > 0.01) { gL16Gen++; L16RestoreDock([[self view] window]); }
    // Bug C fix: after a pull-up that ends with "stay in app", the system first slides the
    // dock to 0 and ~15ms later presents it again -> visible dip/flash. Hold it at 1.0
    // instead; if nobody re-presents it within 0.3s, do the dismissal we swallowed.
    CFTimeInterval now = CACurrentMediaTime();
    if (progress < 0.01 && !interactive && (now - gL16StayEnd) < 0.15 && !L16Flag(@"nodipfix")) {
        L16Log(@"DOCK dipfix: hold at 1.0 instead of dismissing");
        %orig(1.0, animated, interactive, completion);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (gL16PresentSeen < now) {
                L16Log(@"DOCK dipfix: no present arrived, dismissing");
                %orig(0.0, animated, interactive, nil);
            }
        });
        return;
    }
    %orig;
}
- (void)_beginPresentationTransition { L16Log(@"DOCK beginPresentationTransition"); %orig; }
- (void)_endPresentationTransition {
    L16Log(@"DOCK endPresentationTransition");
    %orig;
    // slide-away finished -> dock is off screen, safe to show the window again
    L16RestoreDock([[self view] window]);
}
%end

%hook SBFloatingDockController
- (void)layoutStateTransitionCoordinator:(id)c transitionDidBeginWithTransitionContext:(id)ctx {
    NSString *d = [ctx description];
    L16Log(@"LAYOUT transitionDidBegin %@", d.length > 400 ? [d substringToIndex:400] : d);
    %orig;
}
- (void)layoutStateTransitionCoordinator:(id)c transitionDidEndWithTransitionContext:(id)ctx {
    L16Log(@"LAYOUT transitionDidEnd");
    %orig;
}
- (void)_presentFloatingDockIfDismissedAnimated:(BOOL)a completionHandler:(id)h {
    L16Log(@"DOCK present animated=%d", a);
    gL16PresentSeen = CACurrentMediaTime();
    %orig;
}
- (void)_dismissFloatingDockIfPresentedAnimated:(BOOL)a completionHandler:(id)h {
    L16Log(@"DOCK dismiss animated=%d", a); %orig;
}
%end

// Bug B fix: swiping home from a landscape app. The switcher resolves the zoom-target
// icon through the floating dock, whose window is rotated with the app, so the target
// frame is in the wrong coordinate space (icon stops mid-screen, jumps ~1s later).
// While the switcher is resolving an icon target in landscape, make the floating dock
// report no icons so the home-screen icon view is used. Disable with flag "noiconfilter".

@interface SBFluidSwitcherViewController : UIViewController
@end

static BOOL L16SkipDockIcons(void) {
    return gL16SwitcherLookup > 0 && (L16Orient() == 3 || L16Orient() == 4) && !L16Flag(@"noiconfilter");
}

%hook SBFluidSwitcherViewController
- (id)iconViewForAppLayout:(id)layout {
    gL16SwitcherLookup++;
    id r = %orig;
    gL16SwitcherLookup--;
    L16Log(@"SWITCHER iconViewForAppLayout -> %@ window=%@", NSStringFromClass([r class]), NSStringFromClass([[(UIView *)r window] class]));
    return r;
}
- (CGRect)homeScreenIconFrameForAppLayout:(id)layout {
    gL16SwitcherLookup++;
    CGRect r = %orig;
    gL16SwitcherLookup--;
    static CFTimeInterval last = 0; CFTimeInterval n = CACurrentMediaTime();
    if (n - last > 0.05) { last = n; L16Log(@"SWITCHER homeScreenIconFrame %@", NSStringFromCGRect(r)); }
    return r;
}
- (CGRect)iconImageFrameForAppLayout:(id)layout {
    gL16SwitcherLookup++;
    CGRect r = %orig;
    gL16SwitcherLookup--;
    return r;
}
- (id)homeScreenIconLocationForAppLayout:(id)layout {
    gL16SwitcherLookup++;
    id r = %orig;
    gL16SwitcherLookup--;
    L16Log(@"SWITCHER homeScreenIconLocation %@", r);
    return r;
}
%end

%hook SBFloatingDockController
- (id)firstIconViewForIcon:(id)icon { return L16SkipDockIcons() ? nil : %orig; }
- (id)firstIconViewForIcon:(id)icon excludingLocations:(id)l { return L16SkipDockIcons() ? nil : %orig; }
- (id)firstIconViewForIcon:(id)icon inLocations:(id)l { return L16SkipDockIcons() ? nil : %orig; }
- (id)iconViewForIcon:(id)icon location:(id)l { return L16SkipDockIcons() ? nil : %orig; }
- (BOOL)isDisplayingIcon:(id)icon { return L16SkipDockIcons() ? NO : %orig; }
- (BOOL)isDisplayingIcon:(id)icon inLocation:(id)l { return L16SkipDockIcons() ? NO : %orig; }
- (BOOL)isDisplayingIcon:(id)icon inLocations:(id)l { return L16SkipDockIcons() ? NO : %orig; }
%end

%hook SBHomeGestureFinalDestinationSwitcherModifier
- (void)_updateForGestureDidEndWithEvent:(id)e {
    %orig;
    L16Log(@"GESTURE end finalDestination=%lld reason=%@", [self currentFinalDestination], [self finalDestinationReason]);
    if ([self currentFinalDestination] == 0) gL16StayEnd = CACurrentMediaTime();
}
%end

%hook SBHomeGestureToHomeSwitcherModifier
- (id)initWithTransitionID:(id)tid showingOrAnimatingCardsForFlyIn:(BOOL)fly {
    L16Log(@"GESTURE ToHomeModifier init flyIn=%d", fly);
    return %orig;
}
%end

%hook SBCenterAppIconZoomAnimator
- (double)_iconZoomDelay {
    double d = %orig; L16Log(@"ZOOM iconZoomDelay=%.3f", d);
    return L16Flag(@"nodelay") ? 0.0 : d;
}
- (double)_appZoomDelay {
    double d = %orig; L16Log(@"ZOOM appZoomDelay=%.3f", d);
    return L16Flag(@"nodelay") ? 0.0 : d;
}
- (void)_delayedForRotation { L16Log(@"ZOOM delayedForRotation"); %orig; }
- (void)_prepareAnimation   { L16Log(@"ZOOM center prepare"); %orig; }
- (void)_cleanupAnimation   { L16Log(@"ZOOM center cleanup"); %orig; }
- (void)_performAnimationToFraction:(double)f withCentralAnimationSettings:(id)s
                              delay:(double)d alreadyAnimating:(BOOL)a sharedCompletion:(id)c {
    L16Log(@"ZOOM center perform fraction=%.2f delay=%.3f already=%d", f, d, a);
    %orig;
}
%end

%hook SBScaleIconZoomAnimator
- (void)_prepareAnimation { L16Log(@"ZOOM scale prepare"); %orig; }
- (void)_cleanupAnimation { L16Log(@"ZOOM scale cleanup"); %orig; }
- (void)_performAnimationToFraction:(double)f withCentralAnimationSettings:(id)s
                              delay:(double)d alreadyAnimating:(BOOL)a sharedCompletion:(id)c {
    L16Log(@"ZOOM scale perform fraction=%.2f delay=%.3f already=%d", f, d, a);
    %orig;
}
%end

// ─── Diagnostics: dump method lists of dock/switcher classes to a file ───────
// Output: /var/mobile/Library/Little16-dump.txt (written once, ~20s after respring)

static void L16Dump(void) {
    NSArray *keys = @[@"FloatingDock", @"HomeGesture", @"HomeGrabber", @"FluidSwitcher",
                      @"ZoomAnim", @"AppToHome", @"HomeScreenOpenFolder", @"DockIconListView",
                      @"SBMainSwitcher", @"SBSwitcherAppSuggestion", @"SBDeviceApplicationSceneView"];
    NSMutableString *out = [NSMutableString string];
    unsigned int n = 0;
    Class *list = objc_copyClassList(&n);
    for (unsigned int i = 0; i < n; i++) {
        const char *cn = class_getName(list[i]);
        if (!cn || strncmp(cn, "SB", 2) != 0) continue;
        NSString *name = [NSString stringWithUTF8String:cn];
        BOOL match = NO;
        for (NSString *k in keys) if ([name containsString:k]) { match = YES; break; }
        if (!match) continue;
        Class sup = class_getSuperclass(list[i]);
        [out appendFormat:@"\n@@ %@ : %s\n", name, sup ? class_getName(sup) : "-"];
        unsigned int c = 0;
        Ivar *iv = class_copyIvarList(list[i], &c);
        for (unsigned int j = 0; j < c; j++)
            [out appendFormat:@"  ivar %s %s\n", ivar_getName(iv[j]), ivar_getTypeEncoding(iv[j]) ?: ""];
        free(iv);
        for (int meta = 0; meta < 2; meta++) {
            Class k = meta ? object_getClass(list[i]) : list[i];
            Method *m = class_copyMethodList(k, &c);
            for (unsigned int j = 0; j < c; j++)
                [out appendFormat:@"  %s%s  %s\n", meta ? "+" : "-",
                    sel_getName(method_getName(m[j])), method_getTypeEncoding(m[j]) ?: ""];
            free(m);
        }
    }
    free(list);
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Library/Little16-dump.txt"]) return;
    [out writeToFile:@"/var/mobile/Library/Little16-dump.txt" atomically:YES
            encoding:NSUTF8StringEncoding error:nil];
}

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (![bid isEqualToString:@"com.apple.springboard"]) return;
    %init;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),
        dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{ L16Dump(); });
}
