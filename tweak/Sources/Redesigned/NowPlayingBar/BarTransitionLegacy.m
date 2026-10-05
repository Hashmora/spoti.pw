// The player's open/close stand-ins, below iOS 26 only (SGBelowIOS26). Spotify hides the real bars and moves
// stand-ins; there, a snapshot does not carry a CABackdropLayer and renderInContext: draws no glass at all,
// so the stand-ins get glass of their own, copied pane by pane (a UIVisualEffectView, our SGLegacyGlassView,
// or UIKit's tab bar platter). BarTransition.x calls SGLegacyBackWithGlass first and, below iOS 26, stops
// there: the author's body for iOS 26 is left exactly as it is.
//
// A stand-in that is a snapshot view (the open) cannot take children behind its own picture. There the
// copies live in a holder view right under the stand-in in its superview, and a display link copies the
// stand-in's presentation layer (position, bounds, transform, opacity) onto the holder every frame, so the
// glass rides along with whatever Spotify animates, whether it drives the frame, a transform or the alpha.
//
// While the tab bar's stand-in is on screen the real tab bar is hidden (the superview of its glass pane:
// the tab bar's host, which also holds its icons and film). Spotify does not hide it itself, and a real
// bar left standing under a stand-in that carries glass of its own showed two bars, one moving and one
// not. It comes back when the stand-in leaves its window, or after a failsafe. The real tab bar is kept at an
// alpha of 0.02, not hidden: a hidden view captures its backdrop afresh when it comes back, which on the close
// took a frame, so the bar blinked out and back when the stand-in left.
#import "Core/SGCore.h"
#import "BarTransitionLegacy.h"

static void legacyCollectPanes(UIView *view, NSMutableArray<UIView *> *panes) {
    for (UIView *sub in view.subviews) {
        if (sub.hidden || sub.alpha < 0.01) continue;
        if ([sub isKindOfClass:UIVisualEffectView.class] || [sub isKindOfClass:SGLegacyGlassView.class]
            || [NSStringFromClass(sub.class) hasSuffix:@"PlatterView"]) {
            [panes addObject:sub];
            continue;
        }
        legacyCollectPanes(sub, panes);
    }
}

static UIVisualEffectView *legacyCopyPane(UIView *pane) {
    BOOL platter = ![pane isKindOfClass:UIVisualEffectView.class];
    UIVisualEffect *effect = platter ? SGGlassEffect() : ((UIVisualEffectView *)pane).effect;
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.userInteractionEnabled = NO;
    // The effect does not carry the appearance the pane was drawn in, dark for both bars, and the stand-in
    // would give the copy the system's.
    glass.overrideUserInterfaceStyle = pane.traitCollection.userInterfaceStyle;
    if (platter) {
        SGShapeGlass(glass, pane.bounds.size.height / 2, YES);
    } else if ([pane respondsToSelector:@selector(cornerConfiguration)] && [glass respondsToSelector:@selector(setCornerConfiguration:)]) {
        [glass setCornerConfiguration:[(id)pane cornerConfiguration]];
    }
    glass.layer.cornerRadius = pane.layer.cornerRadius;
    glass.layer.cornerCurve = pane.layer.cornerCurve;
    glass.clipsToBounds = pane.clipsToBounds;
    return glass;
}

// One copy of a pane at `frame` (already in the stand-in's coordinates). A legacy pane is copied as a
// legacy pane with the original's corner radius; it builds its mesh for the copy's own size.
static UIView *copyGlass(UIView *pane, CGRect frame) {
    UIView *glass;
    if ([pane isKindOfClass:SGLegacyGlassView.class]) {
        SGLegacyGlassView *legacy = [[SGLegacyGlassView alloc] initWithFrame:frame];
        legacy.userInteractionEnabled = NO;
        legacy.overrideUserInterfaceStyle = pane.traitCollection.userInterfaceStyle;
        legacy.cornerRadius = pane.layer.cornerRadius;
        glass = legacy;
    } else {
        glass = legacyCopyPane(pane);
        glass.frame = frame;
    }
    glass.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleWidth
        | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleHeight;
    return glass;
}

static CGRect scaledFrame(UIView *pane, UIView *source, CGSize to) {
    CGSize from = source.bounds.size;
    CGFloat sx = from.width > 0 ? to.width / from.width : 1, sy = from.height > 0 ? to.height / from.height : 1;
    CGRect frame = [pane.superview convertRect:pane.frame toView:source];
    return CGRectMake(frame.origin.x * sx, frame.origin.y * sy, frame.size.width * sx, frame.size.height * sy);
}

#pragma mark - stand-in that is a snapshot view

@interface SGStandInGlass : NSObject
@property (nonatomic, weak) UIView *snapshot;
@property (nonatomic, weak) UIView *source;
@property (nonatomic, copy) NSArray<UIView *> *panes;
@property (nonatomic, copy) NSArray<UIView *> *hidden;   // the real views hidden while the stand-in is up
@property (nonatomic, strong) UIView *holder;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) BOOL hideRealBar;                  // the real bar must not show under the stand-in
@property (nonatomic) BOOL watchOnly;                     // the glass already sits inside the stand-in
@property (nonatomic) BOOL seen;                          // the stand-in has been in a window
@property (nonatomic) NSUInteger waited;
@property (nonatomic) CFTimeInterval born;
@end

// Alive while the display link is: it retains its target, and stop breaks that.
static NSMutableSet<SGStandInGlass *> *sg_followers;

// Who has hidden which real view, and how many stand-ins are holding it hidden. Two stand-ins can overlap
// (letting go of a drag makes Spotify's transition hand over a fresh one while the first is still being
// taken down). With a plain hidden flag the second found the view already hidden and took no part in
// it, and the first one's restore then showed the real bar under the second stand-in.
// "Hidden" is an alpha of kHiddenAlpha, so the view's glass keeps drawing; the alpha it had comes back.
static const CGFloat kHiddenAlpha = 0.02;
static NSMapTable<UIView *, NSNumber *> *sg_hiddenCounts;
static NSMapTable<UIView *, NSNumber *> *sg_savedAlpha;

static BOOL hiddenByUs(UIView *view) {
    return [sg_hiddenCounts objectForKey:view] != nil;
}

static void hideCounted(UIView *view) {
    if (!sg_hiddenCounts) {
        sg_hiddenCounts = [NSMapTable weakToStrongObjectsMapTable];
        sg_savedAlpha = [NSMapTable weakToStrongObjectsMapTable];
    }
    NSUInteger count = [sg_hiddenCounts objectForKey:view].unsignedIntegerValue;
    [sg_hiddenCounts setObject:@(count + 1) forKey:view];
    if (count) return;
    [sg_savedAlpha setObject:@(view.alpha) forKey:view];
    [UIView performWithoutAnimation:^{ view.alpha = kHiddenAlpha; }];
}

static void showCounted(UIView *view) {
    NSUInteger count = [sg_hiddenCounts objectForKey:view].unsignedIntegerValue;
    if (count > 1) {
        [sg_hiddenCounts setObject:@(count - 1) forKey:view];
        return;
    }
    CGFloat alpha = [sg_savedAlpha objectForKey:view] ? [sg_savedAlpha objectForKey:view].doubleValue : 1;
    [sg_hiddenCounts removeObjectForKey:view];
    [sg_savedAlpha removeObjectForKey:view];
    [UIView performWithoutAnimation:^{ view.alpha = alpha; }];
}

static void startWatch(void);

@implementation SGStandInGlass

- (void)start {
    if (!sg_followers) sg_followers = [NSMutableSet set];
    [sg_followers addObject:self];
    startWatch();
    self.born = CACurrentMediaTime();
    if (self.hideRealBar) [self hideReal];
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    // Uncapped, or the player's 120 Hz transitions are dragged down to 60 with it (AGENTS.md).
    self.link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self tick:nil];
}

- (void)stop {
    [self.link invalidate];
    self.link = nil;
    [self.holder removeFromSuperview];
    [self restoreReal];
    [sg_followers removeObject:self];
}

// The stand-in has been on screen and is not any more. Also called from the pre-commit watch below, so
// it must not depend on the display link having ticked.
- (BOOL)gone {
    UIView *snapshot = self.snapshot;
    if (!snapshot) return YES;
    if (snapshot.window) self.seen = YES;
    return self.seen && !snapshot.window;
}

// The superview of each real glass pane holds the rest of that bar (icons, film, selection bubble), so
// hiding the pane alone would leave the bar's icons standing under the stand-in's.
- (void)hideReal {
    NSMutableArray<UIView *> *hid = [NSMutableArray array];
    for (UIView *pane in self.panes) {
        UIView *host = pane.superview;
        if (!host || [hid containsObject:host]) continue;
        // Hidden by someone else (Spotify): not ours to bring back. Hidden by another stand-in of ours:
        // join it, so the view stays hidden until the last of them is gone.
        if (host.hidden && !hiddenByUs(host)) continue;
        hideCounted(host);
        [hid addObject:host];
    }
    self.hidden = hid;
}

- (void)restoreReal {
    NSArray<UIView *> *hid = self.hidden;
    self.hidden = nil;
    for (UIView *v in hid) showCounted(v);
}

- (void)attachTo:(UIView *)parent below:(UIView *)snapshot {
    UIView *source = self.source;
    if (!self.holder) {
        self.holder = [UIView new];
        self.holder.userInteractionEnabled = NO;
        self.holder.backgroundColor = UIColor.clearColor;
        CGSize to = snapshot.bounds.size;
        for (UIView *pane in self.panes) {
            if (source) [self.holder addSubview:copyGlass(pane, scaledFrame(pane, source, to))];
        }
    }
    [parent insertSubview:self.holder belowSubview:snapshot];
}

- (void)tick:(CADisplayLink *)link {
    UIView *snapshot = self.snapshot;
    // 30 s is only a failsafe against a stand-in that is never taken down, so a real bar cannot stay hidden.
    if (!snapshot || CACurrentMediaTime() - self.born > 30) { [self stop]; return; }
    UIView *parent = snapshot.superview;
    if (snapshot.window) self.seen = YES;
    if (!parent || (!snapshot.window && self.seen)) {
        // Not added yet (the setter runs before Spotify adds it), or gone for good.
        if (self.seen || ++self.waited > 30) [self stop];
        return;
    }
    if (self.watchOnly) return;
    if (self.holder.superview != parent) [self attachTo:parent below:snapshot];
    // The presentation layer is where the stand-in is drawn right now, mid-animation included.
    CALayer *now = snapshot.layer.presentationLayer ?: snapshot.layer;
    CALayer *mine = self.holder.layer;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mine.anchorPoint = now.anchorPoint;
    mine.bounds = now.bounds;
    mine.position = now.position;
    mine.transform = now.transform;
    mine.opacity = now.opacity;
    mine.hidden = snapshot.layer.hidden;
    [CATransaction commit];
}

@end

// Runs at the end of every run loop turn, before Core Animation commits (its observer is at order 2000000).
// The stand-in is taken down by Spotify in some turn; the real bar has to be shown again in that same
// turn, or one frame goes out with neither (the display link only ticks at the next vsync).
static CFRunLoopObserverRef sg_watch;

static void startWatch(void) {
    if (sg_watch) return;
    sg_watch = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopBeforeWaiting | kCFRunLoopExit, YES, 1000000,
        ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
            if (!sg_followers.count) return;
            for (SGStandInGlass *follower in [sg_followers allObjects]) {
                if ([follower gone]) [follower stop];
            }
        });
    CFRunLoopAddObserver(CFRunLoopGetMain(), sg_watch, kCFRunLoopCommonModes);
}

void SGLegacyBackWithGlass(UIView *snapshot, UIView *source, NSString *what) {
    if (!snapshot || !source) return;
    // Only the tab bar's real view is hidden under its stand-in; the player bar's Spotify hides itself.
    BOOL hideRealBar = [what isEqualToString:@"tab bar"];
    NSMutableArray<UIView *> *panes = [NSMutableArray array];
    legacyCollectPanes(source, panes);
    if (!panes.count) return;

    if (![snapshot isKindOfClass:UIImageView.class]) {
        SGStandInGlass *follower = [SGStandInGlass new];
        follower.snapshot = snapshot;
        follower.source = source;
        follower.panes = panes;
        follower.hideRealBar = hideRealBar;
        [follower start];
        return;
    }

    UIImageView *image = (UIImageView *)snapshot;
    if (!image.image || image.subviews.count) return;
    for (UIView *pane in panes) {
        [image addSubview:copyGlass(pane, scaledFrame(pane, source, image.bounds.size))];
    }
    UIImageView *content = [[UIImageView alloc] initWithImage:image.image];
    content.frame = image.bounds;
    content.contentMode = image.contentMode;
    content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    image.image = nil;
    [image addSubview:content];

    // The glass is inside the stand-in now; all that is left is keeping the real bar out from under it.
    if (hideRealBar) {
        SGStandInGlass *watch = [SGStandInGlass new];
        watch.snapshot = snapshot;
        watch.source = source;
        watch.panes = panes;
        watch.hideRealBar = YES;
        watch.watchOnly = YES;
        [watch start];
    }

    static NSUInteger logged;
    if (logged++ < 4) SGLog(@"player transition: %@ stand-in got %lu glass panes", what, (unsigned long)panes.count);
}
