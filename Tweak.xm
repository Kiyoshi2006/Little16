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

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (![bid isEqualToString:@"com.apple.springboard"]) return;
    %init;
}
