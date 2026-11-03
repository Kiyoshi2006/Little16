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



// ─── EXPERIMENTAL FIXES (v1.0.2) ─────────────────────────────────────────────
// Bug A: dock flashes ~0.3s when re-entering an app (esp. landscape).
//   Hypothesis: dock window is still presented while home -> app transition runs.
//   Fix: hide the dock window while transitioning to an app (toDockVisible == NO),
//   show it again shortly after the transition ends or as soon as the user pulls
//   the dock up.
// Bug B: swiping home from landscape: card shrinks to a wrong place, then ~1s later
//   jumps to the dock. Hypothesis: the zoom animation resolves the app's icon inside
//   the (rotated / not presented) floating dock. Fix: in landscape, while the dock is
//   not presented, pretend the dock displays no icons so the home-screen icon is used.

static BOOL L16Landscape(void) {
    UIApplication *app = [UIApplication sharedApplication];
    long long o = 0;
    if ([app respondsToSelector:@selector(activeInterfaceOrientation)])
        o = ((long long (*)(id, SEL))objc_msgSend)(app, @selector(activeInterfaceOrientation));
    else
        o = (long long)[app statusBarOrientation];
    return o == 3 || o == 4;
}

static NSUInteger gL16Gen = 0;

%hook SBFloatingDockRootViewController
- (void)prepareForTransitionToEnvironmentMode:(long long)mode
                              fromDockVisible:(BOOL)from
                                toDockVisible:(BOOL)to {
    %orig;
    gL16Gen++;
    UIWindow *w = [[self view] window];
    if (w) w.alpha = to ? 1.0 : 0.0;
}
- (void)cleanupAfterTransitionToEnvironmentMode:(long long)mode {
    %orig;
    NSUInteger g = gL16Gen;
    __weak UIWindow *w = [[self view] window];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (g == gL16Gen && w) w.alpha = 1.0;
    });
}
- (void)_setPresentedProgress:(double)progress animated:(BOOL)animated
                  interactive:(BOOL)interactive completion:(id)completion {
    if (progress > 0.01) {
        gL16Gen++;
        UIWindow *w = [[self view] window];
        if (w) w.alpha = 1.0;
    }
    %orig;
}
%end

%hook SBFloatingDockController
- (BOOL)isDisplayingIcon:(id)icon {
    if (L16Landscape() && ![self isFloatingDockPresented]) return NO;
    return %orig;
}
- (BOOL)isDisplayingIcon:(id)icon inLocation:(id)loc {
    if (L16Landscape() && ![self isFloatingDockPresented]) return NO;
    return %orig;
}
- (BOOL)isDisplayingIcon:(id)icon inLocations:(id)locs {
    if (L16Landscape() && ![self isFloatingDockPresented]) return NO;
    return %orig;
}
- (id)firstIconViewForIcon:(id)icon {
    if (L16Landscape() && ![self isFloatingDockPresented]) return nil;
    return %orig;
}
- (id)firstIconViewForIcon:(id)icon excludingLocations:(id)locs {
    if (L16Landscape() && ![self isFloatingDockPresented]) return nil;
    return %orig;
}
- (id)firstIconViewForIcon:(id)icon inLocations:(id)locs {
    if (L16Landscape() && ![self isFloatingDockPresented]) return nil;
    return %orig;
}
- (id)iconViewForIcon:(id)icon location:(id)loc {
    if (L16Landscape() && ![self isFloatingDockPresented]) return nil;
    return %orig;
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
