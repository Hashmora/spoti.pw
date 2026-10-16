// Debug: what of Spotify's own paint is still on the screen. A long press with three fingers anywhere writes one
// report to the log (make log): the screen's controllers, the windows, every visible view that still carries a
// fill of Spotify's (white, opaque or a flat tint) biggest first, and the identifiers and Spotify classes that
// are on the screen, so a page the redesign has not reached shows up without FLEX or a hierarchy dump.
//
//   make log > out/audit.log          then open a screen, long-press with three fingers, once it has settled
//
// Read what it leaves out as well: black page surfaces (SGIsBaseSurface) are the redesign's own, views inside a
// visual effect view or one of ours (class name starting with SG) are glass, and anything smaller than 40x24 or
// off the screen is not looked at. A fill that belongs to a hidden view or to one at alpha 0 never shows.
//
// Compiled in by default. Set SG_AUDIT to 0 (or delete this file) for a build that goes to other people.
// Threading: main thread only.
#import "Core/SGCore.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#ifndef SG_AUDIT
#define SG_AUDIT 1
#endif

#if SG_AUDIT

static char kArmedKey;

static const CGFloat kMinWidth = 40, kMinHeight = 24;
static const NSUInteger kMaxFindings = 150;
static const NSUInteger kMaxLineBytes = 700;

#pragma mark - reading colours and views

static NSString *hexOf(CGColorRef cg) {
    if (!cg) return @"none";
    UIColor *color = [UIColor colorWithCGColor:cg];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if (![color getWhite:&white alpha:&a]) return @"?";
        r = g = b = white;
    }
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X", (unsigned)lround(r * 255), (unsigned)lround(g * 255), (unsigned)lround(b * 255)];
    return a < 0.995 ? [NSString stringWithFormat:@"%@@%.2f", hex, a] : hex;
}

// What a fill is, or nil when it is nothing to report: clear paint and the black the pages are made of.
static NSString *kindOf(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID()) return nil;
    CGFloat alpha = CGColorGetAlpha(color);
    if (alpha < 0.03 || SGIsBaseSurface(color)) return nil;
    if (alpha >= 0.95) return SGIsLightColor(color) ? @"WHITE" : @"OPAQUE";
    return @"TINT";
}

// Glass is not Spotify's paint: a visual effect view, or a view of the mod's own.
static BOOL inGlass(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:UIVisualEffectView.class]) return YES;
        if ([NSStringFromClass(v.class) hasPrefix:@"SG"]) return YES;
    }
    return NO;
}

static BOOL shownIn(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return YES;
}

// Inside a Navigation sheet's pane: where black paint and the opaque flag, which kindOf leaves out, are what hides
// the glass.
static BOOL inSheet(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:@"sheet-view"]) return YES;
    }
    return NO;
}

static NSString *brief(NSString *name) {
    return name.length > 48 ? [[name substringToIndex:48] stringByAppendingString:@"…"] : name;
}

static NSString *parentsOf(UIView *view) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    UIView *v = view.superview;
    for (int i = 0; v && i < 3; i++, v = v.superview) {
        if ([v isKindOfClass:UIWindow.class]) break;
        [names addObject:brief(NSStringFromClass(v.class))];
    }
    return [names componentsJoinedByString:@" < "];
}

static NSArray<UIWindow *> *appWindows(BOOL includeHidden) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (includeHidden || !window.hidden) [windows addObject:window];
        }
    }
    [windows sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel == b.windowLevel) return NSOrderedSame;
        return a.windowLevel < b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
    }];
    return windows;
}

static void chainOf(UIViewController *controller, NSMutableArray<NSString *> *names) {
    for (int guard = 0; controller && guard < 12; guard++) {
        [names addObject:brief(NSStringFromClass(controller.class))];
        UIViewController *next = controller.presentedViewController;
        if (!next && [controller isKindOfClass:UITabBarController.class]) next = ((UITabBarController *)controller).selectedViewController;
        if (!next && [controller isKindOfClass:UINavigationController.class]) next = ((UINavigationController *)controller).topViewController;
        if (!next) next = controller.childViewControllers.lastObject;
        controller = next;
    }
}

#pragma mark - the audit

static void note(NSMutableArray<NSDictionary *> *findings, NSMutableSet<NSString *> *seen, UIView *view, CGRect frame,
                 NSString *kind, NSString *where, CGColorRef color) {
    NSString *ident = view.accessibilityIdentifier;
    NSString *line = [NSString stringWithFormat:@"[%@] %@ %@ %.0fx%.0f @%.0f,%.0f %@%@%@ < %@",
                      kind, where, hexOf(color), frame.size.width, frame.size.height, frame.origin.x, frame.origin.y,
                      brief(NSStringFromClass(view.class)), ident.length ? @" id=" : @"", ident ?: @"", parentsOf(view)];
    // The same fill of the same class and size on every cell of a list is one finding.
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@|%@|%.0f|%.0f", kind, where, hexOf(color), NSStringFromClass(view.class), frame.size.width, frame.size.height];
    if ([seen containsObject:key]) return;
    [seen addObject:key];
    [findings addObject:@{@"area": @(frame.size.width * frame.size.height), @"line": line}];
}

static void inspect(UIWindow *window, NSMutableArray<NSDictionary *> *findings, NSMutableSet<NSString *> *seen,
                    NSMutableSet<NSString *> *ids, NSMutableDictionary<NSString *, NSNumber *> *classes) {
    SGForEachView(window, ^(UIView *view) {
        if (view == window || !shownIn(view)) return;
        CGRect frame = [view convertRect:view.bounds toView:window];
        if (!CGRectIntersectsRect(frame, window.bounds)) return;

        NSString *ident = view.accessibilityIdentifier;
        if (ident.length) [ids addObject:ident];
        NSString *name = NSStringFromClass(view.class);
        if (!([name hasPrefix:@"UI"] || [name hasPrefix:@"_UI"] || [name hasPrefix:@"CA"] || [name hasPrefix:@"SG"])) {
            classes[name] = @(classes[name].integerValue + 1);
        }

        if (frame.size.width < kMinWidth || frame.size.height < kMinHeight || inGlass(view)) return;

        CALayer *layer = view.layer;
        NSString *kind = kindOf(layer.backgroundColor);
        if (kind) note(findings, seen, view, frame, kind, @"bg", layer.backgroundColor);
        else if (inSheet(view)) {
            CGColorRef bg = layer.backgroundColor;
            if (bg && CFGetTypeID(bg) == CGColorGetTypeID() && CGColorGetAlpha(bg) >= 0.95) note(findings, seen, view, frame, @"BLACK", @"bg", bg);
            else if (layer.opaque) note(findings, seen, view, frame, @"FLAG", @"opaque, no fill", NULL);
        }
        if ([layer isKindOfClass:CAShapeLayer.class]) {
            CGColorRef fill = ((CAShapeLayer *)layer).fillColor;
            kind = kindOf(fill);
            if (kind) note(findings, seen, view, frame, kind, @"shape", fill);
        }
        // Layers of Spotify's with no view of their own: the cards' shape layers, a fill painted on a plain layer.
        for (CALayer *sub in layer.sublayers) {
            if (sub.hidden || sub.opacity < 0.01 || [sub.delegate isKindOfClass:UIView.class]) continue;
            if (sub.bounds.size.width < kMinWidth || sub.bounds.size.height < kMinHeight) continue;
            kind = kindOf(sub.backgroundColor);
            if (kind) note(findings, seen, view, frame, kind, @"sublayer-bg", sub.backgroundColor);
            if ([sub isKindOfClass:CAShapeLayer.class]) {
                CGColorRef fill = ((CAShapeLayer *)sub).fillColor;
                kind = kindOf(fill);
                if (kind) note(findings, seen, view, frame, kind, @"sublayer-shape", fill);
            }
        }
    });
}

// Words joined into lines the unified log does not cut.
static void appendWrapped(NSMutableString *out, NSString *label, NSArray<NSString *> *words) {
    [out appendFormat:@"%@ (%lu):\n", label, (unsigned long)words.count];
    NSMutableString *line = [NSMutableString stringWithString:@"  "];
    for (NSString *word in words) {
        if (line.length > 2 && [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + word.length > kMaxLineBytes) {
            [out appendFormat:@"%@\n", line];
            [line setString:@"  "];
        }
        [line appendFormat:@"%@ ", word];
    }
    if (line.length > 2) [out appendFormat:@"%@\n", line];
}

static void runAudit(void) {
    NSMutableString *out = [NSMutableString string];
    NSMutableArray<NSDictionary *> *findings = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSNumber *> *classes = [NSMutableDictionary dictionary];

    NSArray<UIWindow *> *windows = appWindows(YES);
    [out appendString:@"windows:\n"];
    for (UIWindow *window in windows) {
        NSMutableArray<NSString *> *controllers = [NSMutableArray array];
        chainOf(window.rootViewController, controllers);
        [out appendFormat:@"  %@ level=%.0f alpha=%.2f hidden=%d key=%d  %@\n", brief(NSStringFromClass(window.class)), window.windowLevel,
         window.alpha, window.hidden, window.isKeyWindow, [controllers componentsJoinedByString:@" > "]];
        if (window.hidden || window.alpha < 0.01) continue;
        inspect(window, findings, seen, ids, classes);
    }

    [findings sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"area"] compare:a[@"area"]];
    }];
    NSUInteger shown = MIN(findings.count, kMaxFindings);
    [out appendFormat:@"leftover paint (%lu, biggest first%@):\n", (unsigned long)findings.count,
     findings.count > shown ? [NSString stringWithFormat:@", first %lu shown", (unsigned long)shown] : @""];
    for (NSUInteger i = 0; i < shown; i++) [out appendFormat:@"  %@\n", findings[i][@"line"]];

    appendWrapped(out, @"visible ids", [ids.allObjects sortedArrayUsingSelector:@selector(compare:)]);
    NSMutableArray<NSString *> *counted = [NSMutableArray array];
    for (NSString *name in [classes.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [counted addObject:[NSString stringWithFormat:@"%@x%@", brief(name), classes[name]]];
    }
    appendWrapped(out, @"visible classes that are not UIKit's", counted);

    SGLogLong(@"audit", out);
}

#pragma mark - the three-finger long press

@interface SGPaintAuditTrigger : NSObject <UIGestureRecognizerDelegate>
@end

@implementation SGPaintAuditTrigger
- (void)fire:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    dispatch_async(dispatch_get_main_queue(), ^{ runAudit(); });
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;
}
@end

// Every window of the app gets the press once, the popups' windows too as they appear.
static void armWindows(void) {
    static SGPaintAuditTrigger *trigger;
    if (!trigger) trigger = [SGPaintAuditTrigger new];
    for (UIWindow *window in appWindows(YES)) {
        if (objc_getAssociatedObject(window, &kArmedKey)) continue;
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:trigger action:@selector(fire:)];
        press.numberOfTouchesRequired = 3;
        press.minimumPressDuration = 0.8;
        press.cancelsTouchesInView = NO;
        press.delegate = trigger;
        [window addGestureRecognizer:press];
        objc_setAssociatedObject(window, &kArmedKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

__attribute__((constructor)) static void SGPaintAuditInstall(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    void (^arm)(NSNotification *) = ^(NSNotification *n) { armWindows(); };
    (void)[center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:arm];
    (void)[center addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:arm];
}

#endif
