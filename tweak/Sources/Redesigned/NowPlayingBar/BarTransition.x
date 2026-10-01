// The now playing bar and the tab bar keep their glass while the player opens and closes.
//
// Spotify does not move the real bars with the player: it hides them and moves stand-ins, made once at
// the start. -[SPTBarOverlayPresentationTransition setupTransitioningContext:] takes the bar's with
// -snapshotViewAfterScreenUpdates: when the player opens, but with -[CALayer renderInContext:] into a
// UIImageView when it closes, and the tab bar's that way too when it closes over a compact tab bar.
// renderInContext: cannot draw glass (UIVisualEffectView, UIKit's tab bar platters, and our own
// SGLegacyGlassView, a CABackdropLayer), so every close showed the bar's artwork and title and the tab
// bar's glyphs and white film floating on nothing, and the glass popped back in when the real bars
// returned. Checked in the simulator: a snapshot view keeps the glass, a rendered image loses all of it.
//
// A stand-in that is an image gets live glass behind it, copied pane by pane from the view it was
// taken of, with the image moved into a child on top, so it moves and fades with Spotify's own frame
// and alpha changes. Live glass at half alpha still renders (simulator). The tab bar's selection bubble
// is not copied.
//
// A stand-in that is a snapshot view (the open) cannot take children behind its own picture, and below
// iOS 26 a snapshot does not carry a CABackdropLayer either. There the copies live in a holder view
// right under the stand-in in its superview, and a display link copies the stand-in's presentation
// layer (position, bounds, transform, opacity) onto the holder every frame, so the glass rides along
// with whatever Spotify animates, whether it drives the frame, a transform or the alpha.
//
// While the tab bar's stand-in is on screen the real tab bar is hidden (the superview of its glass pane:
// the tab bar's host, which also holds its icons and film). Spotify does not hide it itself, and a real
// bar left standing under a stand-in that carries glass of its own showed two bars, one moving and one
// not. It comes back when the stand-in leaves its window, or after a failsafe. The player bar's real
// view is left alone: Spotify hides that one itself.
//
// MainUI_TabBarUIImpl.CompactOverlayTransition is a Swift animator with the same stand-ins
// (npbSnapshotView, tabBarSnapshotView); which of the two 9.1.78 runs is not known, so both are hooked
// and the log says which fired.
#import "Core/SGCore.h"

@interface SPTBarOverlayPresentationTransition : NSObject
- (UIView *)bottomBarView;
- (UIView *)tabBarView;
- (void)setupTransitioningContext:(id)context;
@end

// The panes to copy: glass views, our legacy glass below iOS 26, and UIKit's tab bar platters, whose
// glass is not a UIVisualEffectView. The source itself may be hidden: Spotify renders the closed bar and
// hides it again before handing the image over.
static void collectPanes(UIView *view, NSMutableArray<UIView *> *panes) {
    for (UIView *sub in view.subviews) {
        if (sub.hidden || sub.alpha < 0.01) continue;
        if ([sub isKindOfClass:UIVisualEffectView.class] || [sub isKindOfClass:SGLegacyGlassView.class]
            || [NSStringFromClass(sub.class) hasSuffix:@"PlatterView"]) {
            [panes addObject:sub];
            continue;
        }
        collectPanes(sub, panes);
    }
}

static UIVisualEffectView *copyPane(UIView *pane) {
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
// legacy pane: its radius is the one updateWithSize: last set on the original, and the mesh is rebuilt
// for the copy's own size.
static UIView *copyGlass(UIView *pane, CGRect frame) {
    UIView *glass;
    if ([pane isKindOfClass:SGLegacyGlassView.class]) {
        SGLegacyGlassView *legacy = [[SGLegacyGlassView alloc] initWithFrame:frame];
        legacy.userInteractionEnabled = NO;
        legacy.overrideUserInterfaceStyle = pane.traitCollection.userInterfaceStyle;
        [legacy updateWithSize:frame.size cornerRadius:pane.layer.cornerRadius capsule:NO clear:NO];
        glass = legacy;
    } else {
        glass = copyPane(pane);
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
static NSMapTable<UIView *, NSNumber *> *sg_hiddenCounts;

static BOOL hiddenByUs(UIView *view) {
    return [sg_hiddenCounts objectForKey:view] != nil;
}

static void hideCounted(UIView *view) {
    if (!sg_hiddenCounts) sg_hiddenCounts = [NSMapTable weakToStrongObjectsMapTable];
    NSUInteger count = [sg_hiddenCounts objectForKey:view].unsignedIntegerValue;
    [sg_hiddenCounts setObject:@(count + 1) forKey:view];
    view.hidden = YES;
}

static void showCounted(UIView *view) {
    NSUInteger count = [sg_hiddenCounts objectForKey:view].unsignedIntegerValue;
    if (count > 1) {
        [sg_hiddenCounts setObject:@(count - 1) forKey:view];
        return;
    }
    [sg_hiddenCounts removeObjectForKey:view];
    view.hidden = NO;
}

// Shows or hides again every real view we are holding hidden, without touching the counts.
static void setHeldHidden(BOOL hidden) {
    for (UIView *view in [sg_hiddenCounts.keyEnumerator allObjects]) view.hidden = hidden;
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
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self tick:nil];
}

- (void)stop {
    NSUInteger restored = self.hidden.count;
    [self.link invalidate];
    self.link = nil;
    [self.holder removeFromSuperview];
    [self restoreReal];
    [sg_followers removeObject:self];
    static NSUInteger logged;
    if (self.hideRealBar && logged++ < 12) {
        SGLog(@"player transition: tab bar stand-in over after %.2fs (snapshot %@, in window %d), %lu real views given back, %lu stand-ins still up",
              CACurrentMediaTime() - self.born, self.snapshot ? @"alive" : @"gone", self.snapshot.window != nil,
              (unsigned long)restored, (unsigned long)sg_followers.count);
    }
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

static void backWithGlass(UIView *snapshot, UIView *source, NSString *what, BOOL hideRealBar) {
    if (!snapshot || !source) return;
    NSMutableArray<UIView *> *panes = [NSMutableArray array];
    collectPanes(source, panes);
    if (hideRealBar) {
        static NSUInteger diagLogged;
        if (diagLogged++ < 12) {
            SGLog(@"player transition: tab bar stand-in source hidden=%d, pane host hidden=%d, followers up=%lu",
                  source.hidden, panes.firstObject.superview.hidden, (unsigned long)sg_followers.count);
        }
        static NSUInteger paneLogged;
        if (paneLogged++ < 6) {
            NSMutableString *list = [NSMutableString string];
            for (UIView *pane in panes) [list appendFormat:@" %@%@", NSStringFromClass(pane.class), NSStringFromCGRect([pane.superview convertRect:pane.frame toView:source])];
            SGLog(@"player transition: tab bar stand-in %@ %@, source %@ hidden=%d, %lu panes:%@",
                  snapshot.class, NSStringFromCGRect(snapshot.frame), NSStringFromCGRect(source.frame), source.hidden, (unsigned long)panes.count, list);
        }
    }
    if (!panes.count) return;

    static NSUInteger logged;
    if (![snapshot isKindOfClass:UIImageView.class]) {
        SGStandInGlass *follower = [SGStandInGlass new];
        follower.snapshot = snapshot;
        follower.source = source;
        follower.panes = panes;
        follower.hideRealBar = hideRealBar;
        [follower start];
        if (logged++ < 8) SGLog(@"player transition: %@ stand-in is a %@, %lu glass panes follow it", what, snapshot.class, (unsigned long)panes.count);
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

    if (logged++ < 8) SGLog(@"player transition: %@ stand-in got %lu glass panes", what, (unsigned long)panes.count);
}

// Says whether Spotify hides the real bar's glass during a transition, which decides if a second copy
// of it is left standing where the bar was.
static void logSource(UIView *source, UIView *stand, NSString *what) {
    static NSUInteger logged;
    if (logged++ >= 6 || !source) return;
    NSMutableString *chain = [NSMutableString string];
    for (UIView *v = source; v; v = v.superview) [chain appendFormat:@" <- %@(h=%d a=%.2f)", NSStringFromClass(v.class), v.hidden, v.alpha];
    SGLog(@"player transition: %@ source%@ | stand-in %@ %@", what, chain, stand.class, NSStringFromCGRect(stand.frame));
}

%hook SPTBarOverlayPresentationTransition
- (void)setBarSnapshotView:(UIView *)view {
    logSource([self bottomBarView], view, @"bar");
    backWithGlass(view, [self bottomBarView], @"bar", NO);
    %orig;
}
- (void)setTabBarSnapshotView:(UIView *)view {
    logSource([self tabBarView], view, @"tab bar");
    backWithGlass(view, [self tabBarView], @"tab bar", YES);
    %orig;
}
%end

// A new transition (letting go of a drag hands over a fresh one) takes its stand-ins from the real bars.
// If an earlier stand-in of ours still holds the real tab bar hidden, the snapshot / renderInContext: is
// taken of a hidden view and comes out empty. So the bars are shown for the duration of the setup and
// hidden again before the run loop turn ends, so no frame with the real bar goes out.
%hook SPTBarOverlayPresentationTransition
- (void)setupTransitioningContext:(id)context {
    setHeldHidden(NO);
    %orig;
    setHeldHidden(YES);
}
%end

static id ivarNamed(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    return ivar ? object_getIvar(object, ivar) : nil;
}

%hook _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition
- (void)animateTransition:(id)context {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"player transition: CompactOverlayTransition animates, snapshots %@ / %@",
                                  [ivarNamed(self, "npbSnapshotView") class], [ivarNamed(self, "tabBarSnapshotView") class]); });
    backWithGlass(ivarNamed(self, "npbSnapshotView"), ivarNamed(self, "npbView"), @"bar", NO);
    backWithGlass(ivarNamed(self, "tabBarSnapshotView"), ivarNamed(self, "tabBarView"), @"tab bar", YES);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"SPTBarOverlayPresentationTransition",
        @"_TtC19MainUI_TabBarUIImpl24CompactOverlayTransition",
    ]);
}
