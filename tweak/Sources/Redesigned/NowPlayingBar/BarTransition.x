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
// MainUI_TabBarUIImpl.CompactOverlayTransition is a Swift animator with the same stand-ins
// (npbSnapshotView, tabBarSnapshotView); which of the two 9.1.78 runs is not known, so both are hooked
// and the log says which fired.
#import "Core/SGCore.h"

@interface SPTBarOverlayPresentationTransition : NSObject
- (UIView *)bottomBarView;
- (UIView *)tabBarView;
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
@property (nonatomic, strong) UIView *holder;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) NSUInteger waited;
@end

// Alive while the display link is: it retains its target, and stop breaks that.
static NSMutableSet<SGStandInGlass *> *sg_followers;

@implementation SGStandInGlass

- (void)start {
    if (!sg_followers) sg_followers = [NSMutableSet set];
    [sg_followers addObject:self];
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self.link invalidate];
    self.link = nil;
    [self.holder removeFromSuperview];
    [sg_followers removeObject:self];
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
    if (!snapshot) { [self stop]; return; }
    UIView *parent = snapshot.superview;
    if (!parent) {
        // Not on screen yet (the setter runs before Spotify adds it), or gone for good.
        if (self.holder.superview || ++self.waited > 120) [self stop];
        return;
    }
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

static void backWithGlass(UIView *snapshot, UIView *source, NSString *what) {
    if (!snapshot || !source) return;
    NSMutableArray<UIView *> *panes = [NSMutableArray array];
    collectPanes(source, panes);
    if (!panes.count) return;

    static NSUInteger logged;
    if (![snapshot isKindOfClass:UIImageView.class]) {
        SGStandInGlass *follower = [SGStandInGlass new];
        follower.snapshot = snapshot;
        follower.source = source;
        follower.panes = panes;
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
    backWithGlass(view, [self bottomBarView], @"bar");
    %orig;
}
- (void)setTabBarSnapshotView:(UIView *)view {
    logSource([self tabBarView], view, @"tab bar");
    backWithGlass(view, [self tabBarView], @"tab bar");
    %orig;
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
    backWithGlass(ivarNamed(self, "npbSnapshotView"), ivarNamed(self, "npbView"), @"bar");
    backWithGlass(ivarNamed(self, "tabBarSnapshotView"), ivarNamed(self, "tabBarView"), @"tab bar");
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
