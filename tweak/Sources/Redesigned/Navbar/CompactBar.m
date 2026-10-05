// Compact bar: scrolling a tab's page down folds the glass bar and the now playing card into one row, the
// way iOS 26's tabBarMinimizeBehavior does with a bottom accessory: a circle with the open tab's glyph, the
// player between, a circle with Search. Scrolling up, reaching the top, a tab change or the player opening
// puts the two bars back. Off unless the Navbar page's switch is on (SGRKeyNavbarCompact).
//
// The real bars are never moved or resized. TabBar.x rewrites the capsule's frames on every layout pass and
// Spotify's constraints own the now playing card's, so a frame or a transform set from here would be set
// back (or set wrong, a frame set through a transform). They only fade, and stop taking touches while
// faded. The row is a view of its own in the stock bar's view, over the capsule's platter, made of glass
// shapes like TabBar.x's; what it shows is read off the real bars (SGRNowPlayingState, the tab's glyphs)
// and its taps are replayed on them (SGRNowPlayingTogglePlay, SGRNowPlayingOpen, SGRTabBarSideTap).
//
// Scrolling is read from a pan recognizer on the window that never takes a touch from anyone, not from
// the scroll views: the direction of the finger is all that is needed, and there is no delegate or
// contentOffset of Spotify's to hook. The page's own scroll view is looked up under the finger to tell a
// scroll of the page from a swipe on a carousel or a drag on the bars, and to know when it is at its top.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"

static const CGFloat kRowHeight = 52;       // the circles' diameter and the player's height
static const CGFloat kRowGap = 8;
static const CGFloat kRowMargin = 16;       // the same gap at each side as the capsule's
static const CGFloat kFoldDistance = 24;    // finger travel up before the bars fold
static const CGFloat kUnfoldDistance = 12;  // finger travel down before they unfold
static const CGFloat kFoldMinOffset = 60;   // never folded this close to the top
static const NSTimeInterval kDuration = 0.38;

static char kGlassKey, kFilmKey;
static BOOL sg_collapsed;

#pragma mark - the row

@interface SGRCompactStrip : UIView
@property (nonatomic, strong) UIView *leftCircle, *rightCircle, *pill;
@property (nonatomic, strong) UIImageView *leftGlyph, *rightGlyph, *artwork;
@property (nonatomic, strong) UILabel *titleLabel, *artistLabel;
@property (nonatomic, strong) UIButton *playButton;
- (void)reload;
@end

static void glassBehind(UIView *host, CGFloat radius) {
    UIView *glass = SGGlassFor(host, &kGlassKey);
    // Dark whatever the system is set to, as TabBar.x's capsule is.
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if (!CGRectEqualToRect(glass.frame, host.bounds)) glass.frame = host.bounds;
    SGShapeGlass(glass, radius, NO);
    SGRGlassFilm(host, &kFilmKey, glass, radius);
}

static UIImageView *glyphView(void) {
    UIImageView *view = [UIImageView new];
    view.contentMode = UIViewContentModeCenter;
    view.tintColor = UIColor.whiteColor;
    view.userInteractionEnabled = NO;
    return view;
}

@implementation SGRCompactStrip

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _leftCircle = [UIView new];
    _leftGlyph = glyphView();
    [_leftCircle addSubview:_leftGlyph];
    [_leftCircle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedLeft)]];

    _rightCircle = [UIView new];
    _rightGlyph = glyphView();
    [_rightCircle addSubview:_rightGlyph];
    [_rightCircle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedRight)]];

    _pill = [UIView new];
    _pill.clipsToBounds = NO;
    [_pill addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedPill)]];
    _artwork = [UIImageView new];
    _artwork.contentMode = UIViewContentModeScaleAspectFill;
    _artwork.clipsToBounds = YES;
    _artwork.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = UIColor.whiteColor;
    _artistLabel = [UILabel new];
    _artistLabel.font = [UIFont systemFontOfSize:13];
    _artistLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _playButton.tintColor = UIColor.whiteColor;
    [_playButton addTarget:self action:@selector(tappedPlay) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *v in @[_artwork, _titleLabel, _artistLabel, _playButton]) [_pill addSubview:v];

    for (UIView *v in @[_pill, _leftCircle, _rightCircle]) [self addSubview:v];
    return self;
}

// The strip is as wide as the capsule's room and the gaps between its pieces must not eat touches meant
// for the page under it.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, h = kRowHeight;
    self.leftCircle.frame = CGRectMake(0, 0, h, h);
    self.rightCircle.frame = CGRectMake(width - h, 0, h, h);
    CGFloat pillX = self.pill.hidden ? 0 : h + kRowGap;
    self.pill.frame = CGRectMake(pillX, 0, MAX(0, width - 2 * pillX), h);

    self.leftGlyph.frame = self.leftCircle.bounds;
    self.rightGlyph.frame = self.rightCircle.bounds;
    glassBehind(self.leftCircle, h / 2);
    glassBehind(self.rightCircle, h / 2);
    if (self.pill.hidden) return;
    glassBehind(self.pill, h / 2);

    CGFloat art = 36, inset = (h - art) / 2;
    self.artwork.frame = CGRectMake(inset, inset, art, art);
    self.artwork.layer.cornerRadius = art / 2;
    CGFloat button = 44;
    self.playButton.frame = CGRectMake(self.pill.bounds.size.width - button - 6, (h - button) / 2, button, button);
    CGFloat textX = CGRectGetMaxX(self.artwork.frame) + 10;
    CGFloat textWidth = MAX(0, CGRectGetMinX(self.playButton.frame) - textX);
    BOOL twoLines = self.artistLabel.text.length > 0;
    self.titleLabel.frame = CGRectMake(textX, twoLines ? 8 : 16, textWidth, 20);
    self.artistLabel.frame = CGRectMake(textX, 27, textWidth, 17);
}

- (void)reload {
    self.leftGlyph.image = SGRTabBarCurrentGlyph();
    self.rightGlyph.image = SGRTabBarSideGlyph();
    NSString *title = nil, *artist = nil;
    UIImage *art = nil;
    BOOL playing = NO;
    BOOL has = SGRNowPlayingState(&title, &artist, &art, &playing);
    self.pill.hidden = !has;
    if (has) {
        self.titleLabel.text = title;
        self.artistLabel.text = artist;
        if (art) self.artwork.image = art;
        UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold];
        [self.playButton setImage:[UIImage systemImageNamed:playing ? @"pause.fill" : @"play.fill" withConfiguration:size] forState:UIControlStateNormal];
    }
    [self setNeedsLayout];
}

- (void)tappedLeft {
    SGRCompactBarSetCollapsed(NO, YES);
}

- (void)tappedRight {
    SGRTabBarSideTap();
    SGRCompactBarSetCollapsed(NO, YES);
}

- (void)tappedPill {
    SGRNowPlayingOpen();
}

- (void)tappedPlay {
    SGRNowPlayingTogglePlay();
    // Spotify repaints its button a moment after the tap; the row reads it again then.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self reload];
    });
}

@end

static __weak SGRCompactStrip *sg_strip;

static SGRCompactStrip *stripIn(UIView *stockBar) {
    SGRCompactStrip *strip = sg_strip;
    if (strip && strip.superview == stockBar) return strip;
    strip = [[SGRCompactStrip alloc] initWithFrame:CGRectMake(0, 0, 100, kRowHeight)];
    strip.alpha = 0;
    strip.hidden = YES;
    strip.userInteractionEnabled = NO;
    [stockBar addSubview:strip];
    sg_strip = strip;
    return strip;
}

#pragma mark - folding

void SGRCompactBarSetCollapsed(BOOL collapsed, BOOL animated) {
    if (collapsed && !SGHidden(SGRKeyNavbarCompact)) collapsed = NO;
    SGRCompactStrip *strip = sg_strip;
    UIView *host = SGRTabBarCapsule(NULL);
    if (collapsed && (!strip || !host)) return;
    if (collapsed == sg_collapsed) return;
    sg_collapsed = collapsed;

    UIView *card = SGRNowPlayingContainerView();
    if (collapsed) {
        [strip reload];
        strip.hidden = NO;
        [strip layoutIfNeeded];
        // Comes in from a little smaller than it ends, over the bars fading out.
        if (strip.alpha < 0.01) strip.transform = CGAffineTransformMakeScale(0.9, 0.9);
    }
    host.userInteractionEnabled = !collapsed;
    card.userInteractionEnabled = !collapsed;
    strip.userInteractionEnabled = collapsed;

    void (^apply)(void) = ^{
        host.alpha = collapsed ? 0 : 1;
        card.alpha = collapsed ? 0 : 1;
        strip.alpha = collapsed ? 1 : 0;
        strip.transform = collapsed ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.9, 0.9);
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (!sg_collapsed) strip.hidden = YES;
    };
    if (animated) {
        [UIView animateWithDuration:kDuration delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:apply completion:done];
    } else {
        // No animation also takes an animation already running off the layers.
        [strip.layer removeAllAnimations];
        apply();
        done(YES);
    }
}

void SGRCompactBarNowPlayingChanged(void) {
    if (sg_collapsed) [sg_strip reload];
}

#pragma mark - reading the scroll

@interface SGRCompactWatcher : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIScrollView *list;
@property (nonatomic) CGFloat lastY, travel;
@end

@implementation SGRCompactWatcher

// The page's list under the finger: the first scroll view up the tree that is tall and wide enough to be
// the page and has more to scroll than its own height, so a carousel in a row is passed over for the list
// the row is in. Only inside the tab container, so the player's own lists never count.
- (UIScrollView *)pageListUnder:(UIView *)hit in:(UIWindow *)window {
    UIView *container = SGRTabBarContainerView();
    if (!container || !hit || !SGIsInside(hit, container)) return nil;
    for (UIView *v = hit; v && v != container; v = v.superview) {
        if (![v isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *list = (UIScrollView *)v;
        CGSize size = list.bounds.size;
        if (size.width >= window.bounds.size.width * 0.9 && size.height >= window.bounds.size.height * 0.4
            && list.contentSize.height > size.height + 1) return list;
    }
    return nil;
}

- (void)pan:(UIPanGestureRecognizer *)pan {
    UIWindow *window = (UIWindow *)pan.view;
    CGFloat y = [pan translationInView:window].y;
    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            self.lastY = y;
            self.travel = 0;
            // Nothing is read while something is presented over the tabs (the player, a sheet).
            UIResponder *owner = SGRTabBarContainerView().nextResponder;
            BOOL covered = [owner isKindOfClass:UIViewController.class] && ((UIViewController *)owner).presentedViewController;
            UIView *hit = [window hitTest:[pan locationInView:window] withEvent:nil];
            self.list = SGHidden(SGRKeyNavbarCompact) && !covered ? [self pageListUnder:hit in:window] : nil;
            break;
        }
        case UIGestureRecognizerStateChanged: {
            UIScrollView *list = self.list;
            CGFloat dy = y - self.lastY;
            self.lastY = y;
            if (!list || !SGHidden(SGRKeyNavbarCompact) || fabs(dy) < 0.1) return;
            // The finger going up scrolls the page down. A change of direction starts the count again.
            if ((dy < 0) != (self.travel < 0)) self.travel = 0;
            self.travel += dy;
            CGFloat top = -list.adjustedContentInset.top;
            CGFloat offset = list.contentOffset.y;
            if (offset <= top + 1) {
                SGRCompactBarSetCollapsed(NO, YES);
                self.travel = 0;
            } else if (self.travel < -kFoldDistance && offset > top + kFoldMinOffset) {
                SGRCompactBarSetCollapsed(YES, YES);
            } else if (self.travel > kUnfoldDistance) {
                SGRCompactBarSetCollapsed(NO, YES);
            }
            break;
        }
        default:
            self.list = nil;
            break;
    }
}

// Never takes a touch from anyone, and never gets one meant for the bars themselves.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *stock = SGRTabBarStock();
    UIView *card = SGRNowPlayingContainerView();
    return !(stock && SGIsInside(touch.view, stock)) && !(card && SGIsInside(touch.view, card));
}

@end

static SGRCompactWatcher *sg_watcher;
static __weak UIPanGestureRecognizer *sg_pan;   // nothing here runs unless TabBar.x does, which is the redesign's

static void watchScrolling(UIWindow *window) {
    if (!window || sg_pan.view == window) return;
    if (!sg_watcher) sg_watcher = [SGRCompactWatcher new];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:sg_watcher action:@selector(pan:)];
    pan.delegate = sg_watcher;
    pan.cancelsTouchesInView = NO;
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    [window addGestureRecognizer:pan];
    sg_pan = pan;
    SGLog(@"compact bar: watching scrolls on %@", NSStringFromClass(window.class));
}

#pragma mark - TabBar.x's pass

// Called at the end of every sync of the glass bar: the row follows the platter, and stays over it.
void SGRCompactBarSynced(UIView *stockBar) {
    if (!SGHidden(SGRKeyNavbarCompact)) {
        // The switch turned off while the bars were folded: they come back, with no animation to wait for.
        if (sg_collapsed) SGRCompactBarSetCollapsed(NO, NO);
        return;
    }
    CGRect platter = CGRectZero;
    if (!SGRTabBarCapsule(&platter) || CGRectIsEmpty(platter)) return;
    SGRCompactStrip *strip = stripIn(stockBar);
    // bounds and center, not frame: the row is scaled while it comes in, and a frame set through a
    // transform is not the frame that was asked for.
    CGRect bounds = CGRectMake(0, 0, stockBar.bounds.size.width - 2 * kRowMargin, kRowHeight);
    if (!CGRectEqualToRect(strip.bounds, bounds)) strip.bounds = bounds;
    CGPoint center = CGPointMake(CGRectGetMidX(stockBar.bounds), CGRectGetMidY(platter));
    if (!CGPointEqualToPoint(strip.center, center)) strip.center = center;
    if (stockBar.subviews.lastObject != strip) [stockBar bringSubviewToFront:strip];
    if (sg_collapsed) [strip reload];
    watchScrolling(stockBar.window);
}
