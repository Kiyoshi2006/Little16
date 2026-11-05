/*
 * Little16CC — companion to the original Little16.
 * Lets you close Control Center by swiping up from the bottom edge: while Control Center
 * is visible, Little16's home-gesture recognizer yields and dismisses it instead.
 */

#import <UIKit/UIKit.h>
#import <objc/message.h>

static BOOL CCVisible(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in [(UIWindowScene *)scene windows]) {
            if (w.hidden || w.alpha <= 0.01) continue;
            if ([NSStringFromClass([w class]) containsString:@"ControlCenter"]) return YES;
            UIViewController *rvc = w.rootViewController;
            if (rvc) {
                NSString *rn = NSStringFromClass([rvc class]);
                if ([rn containsString:@"ControlCenter"] || [rn containsString:@"CCUI"]) return YES;
            }
        }
    }
    return NO;
}

static void CCDismiss(void) {
    Class c = NSClassFromString(@"SBControlCenterController");
    if (![c respondsToSelector:@selector(sharedInstance)]) return;
    id ctl = ((id (*)(id, SEL))objc_msgSend)(c, @selector(sharedInstance));
    if (!ctl) return;
    if ([ctl respondsToSelector:@selector(dismissAnimated:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(ctl, @selector(dismissAnimated:), YES);
    else if ([ctl respondsToSelector:@selector(_dismissAnimated:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(ctl, @selector(_dismissAnimated:), YES);
    else if ([ctl respondsToSelector:@selector(dismissAnimated:completion:)])
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(ctl, @selector(dismissAnimated:completion:), YES, nil);
}

%hook SBHomeGesturePanGestureRecognizer
- (BOOL)_shouldBegin {
    BOOL r = %orig;
    if (r && CCVisible()) {
        CCDismiss();
        return NO;
    }
    return r;
}
%end
