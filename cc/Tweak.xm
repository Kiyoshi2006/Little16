/*
 * Little16CC — companion to the ORIGINAL Little16 (does not replace it).
 *
 * Problem: with Little16's home gesture on a home-button iPhone, the ~0.5cm strip at the
 * bottom edge belongs to the home-gesture recognizer. While Control Center is open it
 * swallows the swipe and does nothing, so Control Center cannot be closed from that strip.
 *
 * Fix: while Control Center is visible, the home-gesture recognizer refuses to begin and
 * dismisses Control Center itself.
 *
 * Files (optional):
 *   /var/mobile/Library/Little16CC-flags.txt  containing "off" disables the fix
 *   /var/mobile/Library/Little16CC-trace.txt  log of what happened (reset on respring)
 *   /var/mobile/Library/Little16CC-dump.txt   control-center / gesture class dump (once)
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL CCFlag(NSString *name) {
    static NSString *cache = nil;
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!cache || now - last > 1.0) {
        cache = [NSString stringWithContentsOfFile:@"/var/mobile/Library/Little16CC-flags.txt"
                                          encoding:NSUTF8StringEncoding error:nil] ?: @"";
        last = now;
    }
    return [cache containsString:name];
}

static void CCLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static void CCLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%.3f %@\n", CACurrentMediaTime(), m];
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("little16cc.trace", DISPATCH_QUEUE_SERIAL);
        [@"" writeToFile:@"/var/mobile/Library/Little16CC-trace.txt" atomically:YES
                encoding:NSUTF8StringEncoding error:nil];
    });
    dispatch_async(q, ^{
        FILE *f = fopen("/var/mobile/Library/Little16CC-trace.txt", "a");
        if (f) { fputs([line UTF8String], f); fclose(f); }
    });
}

static BOOL CCWindowIsControlCenter(UIWindow *w, NSMutableString *dbg) {
    NSString *cn = NSStringFromClass([w class]);
    NSString *rn = NSStringFromClass([[w rootViewController] class]);
    BOOL isCC = [cn containsString:@"ControlCenter"] || [rn containsString:@"ControlCenter"] || [rn containsString:@"CCUI"];
    [dbg appendFormat:@"[%@ rvc=%@ hidden=%d alpha=%.2f] ", cn, rn, w.hidden, w.alpha];
    return isCC && !w.hidden && w.alpha > 0.01;
}

static BOOL CCVisible(void) {
    NSMutableString *dbg = [NSMutableString string];
    BOOL vis = NO;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in [(UIWindowScene *)sc windows])
            if (CCWindowIsControlCenter(w, dbg)) vis = YES;
    }
    CCLog(@"CC visible=%d windows: %@", vis, dbg);
    return vis;
}

static void CCDismiss(void) {
    Class c = NSClassFromString(@"SBControlCenterController");
    id ctl = nil;
    if ([c respondsToSelector:@selector(sharedInstance)])
        ctl = ((id (*)(id, SEL))objc_msgSend)(c, @selector(sharedInstance));
    if (!ctl) { CCLog(@"dismiss: no controller"); return; }
    SEL cands[] = { @selector(dismissAnimated:), @selector(_dismissAnimated:) };
    for (int i = 0; i < 2; i++) {
        if ([ctl respondsToSelector:cands[i]]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(ctl, cands[i], YES);
            CCLog(@"dismiss via %s", sel_getName(cands[i]));
            return;
        }
    }
    SEL c2 = @selector(dismissAnimated:completion:);
    if ([ctl respondsToSelector:c2]) {
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(ctl, c2, YES, nil);
        CCLog(@"dismiss via dismissAnimated:completion:");
        return;
    }
    CCLog(@"dismiss: no known selector on %@", NSStringFromClass([ctl class]));
}

%hook SBHomeGesturePanGestureRecognizer
- (BOOL)_shouldBegin {
    BOOL r = %orig;
    if (r && !CCFlag(@"off") && CCVisible()) {
        CCLog(@"home gesture blocked: control center visible -> dismissing");
        CCDismiss();
        return NO;
    }
    return r;
}
%end

static void CCDump(void) {
    NSString *path = @"/var/mobile/Library/Little16CC-dump.txt";
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSArray *keys = @[@"ControlCenter", @"CCUI", @"SystemGesture", @"ScreenEdge", @"CoverSheetPresent"];
    NSMutableString *out = [NSMutableString string];
    unsigned int n = 0;
    Class *list = objc_copyClassList(&n);
    for (unsigned int i = 0; i < n; i++) {
        const char *cn = class_getName(list[i]);
        if (!cn || (strncmp(cn, "SB", 2) != 0 && strncmp(cn, "CCUI", 4) != 0 && strncmp(cn, "CSCover", 7) != 0)) continue;
        NSString *name = [NSString stringWithUTF8String:cn];
        BOOL match = NO;
        for (NSString *k in keys) if ([name containsString:k]) { match = YES; break; }
        if (!match) continue;
        Class sup = class_getSuperclass(list[i]);
        [out appendFormat:@"\n@@ %@ : %s\n", name, sup ? class_getName(sup) : "-"];
        unsigned int c = 0;
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
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (![bid isEqualToString:@"com.apple.springboard"]) return;
    %init;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),
        dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{ CCDump(); });
}
