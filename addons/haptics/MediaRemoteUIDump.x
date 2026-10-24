// Vitrine Addon in MediaRemoteUI, the process that draws the lock screen's player and its large cover (SpringBoard only
// hosts its scene: the cover sheet's own tree has neither, the phone, 2026-10-24). For now it only says what the
// player's views are, so the Canvas can be put in the large cover's place there: as a cover lays out, its window's
// tree goes to the system log a line a view ("[vitrine-addon mrui] n line depth class frame ..."), a second after the
// last change, four times a launch at most. Nothing is hooked but the cover view's layout.
#import <UIKit/UIKit.h>

static const NSUInteger kDumps = 4;
static NSUInteger sg_dumps;

static void dumpView(UIView *view, int depth, NSUInteger *line, NSUInteger dump) {
    if (depth > 40 || *line > 1200) return;
    CGRect frame = view.frame;
    NSMutableString *text = [NSMutableString stringWithFormat:@"[vitrine-addon mrui] %lu %lu %*s%@ {%.0f,%.0f,%.0f,%.0f}",
                             (unsigned long)dump, (unsigned long)(*line)++, depth * 2, "", NSStringFromClass(view.class),
                             frame.origin.x, frame.origin.y, frame.size.width, frame.size.height];
    if (view.hidden) [text appendString:@" hidden"];
    if (view.alpha < 0.99) [text appendFormat:@" a=%.2f", view.alpha];
    if (view.accessibilityIdentifier.length) [text appendFormat:@" id=%@", view.accessibilityIdentifier];
    if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image) {
        CGSize size = ((UIImageView *)view).image.size;
        [text appendFormat:@" img=%.0fx%.0f", size.width, size.height];
    }
    NSLog(@"%@", text);
    for (UIView *sub in view.subviews) dumpView(sub, depth + 1, line, dump);
}

static void dumpSoon(UIView *from) {
    static NSUInteger asked;
    if (sg_dumps >= kDumps) return;
    NSUInteger mine = ++asked;
    __weak UIView *weak = from;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = weak.window;
        if (mine != asked || sg_dumps >= kDumps || !window) return;
        NSUInteger dump = ++sg_dumps, line = 0;
        NSLog(@"[vitrine-addon mrui] %lu begin, %@ %@", (unsigned long)dump, NSStringFromClass(window.class), NSStringFromCGRect(window.bounds));
        dumpView(window, 0, &line, dump);
        NSLog(@"[vitrine-addon mrui] %lu end, %lu views", (unsigned long)dump, (unsigned long)line);
    });
}

%hook MRUArtworkView
- (void)layoutSubviews {
    %orig;
    dumpSoon((UIView *)self);
}
%end

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MediaRemoteUI"]) return;
    NSLog(@"[vitrine-addon mrui] in MediaRemoteUI, MRUArtworkView %@", NSClassFromString(@"MRUArtworkView") ? @"found" : @"not found");
    if (NSClassFromString(@"MRUArtworkView")) %init;
}
