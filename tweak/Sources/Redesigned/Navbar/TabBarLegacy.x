// Tab bar below iOS 26, for the redesign: Spotify's own bar stays where it is but goes invisible, and a system
// UITabBar sits on top of it as a floating capsule with a selection pill, drag-to-switch and Create's menu
// handled (ported from the legacy-glass branch). The capsule is drawn on SGGlassFor's pane, so with Legacy
// Liquid Glass off it is the plain dark blur every other pane of the redesign falls back to, and with it on it
// is SGLegacyGlassView. Nothing here depends on which one it is.
//
// TabBar.x is the other bar: on iOS 26+ UIKit draws real Liquid Glass for it and this file stays out. Below 26
// its system bar has no platters to hang the minimized bar's circles on, and drew them as bare slabs of
// blur. The hooks here are in a group that only runs where SGRLegacyTabBarOn() says so, and TabBar.x's own
// hooks do not run then, so exactly one of the two bars is ever in place. The glass kind is read once at
// launch, so changing the switch in Mod Settings takes effect on the next launch.
//
// A page scrolled down minimizes the bar to a circle holding the open tab at the leading end, a circle at
// the trailing end when tabs are set apart (Split tabs), and the now playing card between them, as TabBar.x
// does on 26. See "compact".
//
// The last tab set apart is never on the capsule: it has a round button of its own at the trailing end, beside
// the capsule on the full bar and in the compact row when minimized, as the Music app's Search has. The
// capsule holds the other tabs only.
//
// A tab picked on the system bar is passed on as a tap on the hidden Spotify item it mirrors, and the
// system bar's selection follows whichever Spotify label is painted white. Navbar.x composes the
// hidden row, so its order, hidden tabs and tabs of the mod's own carry over.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView of
//   ElementContentView<TabBarItemElement>, each with an SPTEncoreIconView and an SPTEncoreLabel.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Settings/SGPage.h"
#import "Headers/SPTEncoreIconView.h"
#import <objc/message.h>

static char kBarKey, kHostKey, kNavGlassKey, kNavTintKey, kSelPillKey, kRetriesKey, kGlyphOverlayKey, kOutlineLiveKey, kFilledLiveKey, kCreateDiscKey, kGlyphsTakenKey;
static char kCirclePaneKey, kCircleFilmKey, kLeadKey, kTrailKey;
// The bar is a floating capsule, not a full-width slab.
static const CGFloat kNavGlassMargin = 16;        // gap at each side
static const CGFloat kNavGlassBottomMargin = 8;   // gap under it, and over it to the now playing card
// The capsule itself, never the safe-area room under it: glassHeight() can be 83pt on a Face ID phone
// (harness/tabbar/README.md) because it includes the home-indicator strip. 64pt is Telegram's pill (a 56pt
// item row with 4pt inside, TabBarComponent.swift). Without labels it is shorter, and UIKit still lays the
// icon out as if one sat below it, so the icon is nudged down by kNavIconOnlyImageShift (not yet checked
// on a device: tune the two together).
static const CGFloat kNavPlatterHeight = 64;
static const CGFloat kNavPlatterHeightIconOnly = 52;
static const CGFloat kNavIconOnlyImageShift = 6;
static const CGFloat kNavItemSpacing = 4;
static const CGFloat kNavCircleSide = 48;   // the compact bar's circles before the now playing card has a radius to follow
static const CGFloat kNavItemWidth = 90;    // fixed, so the capsule hugs its items instead of stretching them
static const CGFloat kSelPillInset = 3;     // gap between the selection pill and the capsule's edge
static __weak UIView *sg_stockBar;
static CGFloat sg_room, sg_glassHeight;   // see "room for the glass bar"
// See "compact". The circles' frames in the host's coordinates, the trailing one empty when no tab is set apart.
static BOOL sg_minimized;
static CGRect sg_leadFrame, sg_trailFrame;

// Components/TabSelectionRecognizer/Sources/TabSelectionRecognizer.swift, ported as-is: state goes to
// Began the instant a finger touches down (no distance or duration threshold the way a pan or a long
// press has), and Changed on every move after that, so a caller can follow the finger from frame one.
@interface SGRLegacyTabDragRecognizer : UIGestureRecognizer
@property (nonatomic) CGPoint currentLocation;
@property (nonatomic) BOOL moved;
@end

@implementation SGRLegacyTabDragRecognizer

- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithTarget:target action:action];
    if (self) {
        self.delaysTouchesBegan = NO;
        self.delaysTouchesEnded = NO;
        // Explicit even though YES is the default: UITabBar has its own internal touch handling for
        // tapping items, and without this our recognizer and that internal handling can both react to
        // the same touch, racing each other -- that race is what made the drag/tap register only
        // sometimes.
        self.cancelsTouchesInView = YES;
    }
    return self;
}

- (void)reset {
    [super reset];
    self.moved = NO;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    self.currentLocation = [touches.anyObject locationInView:self.view];
    self.state = UIGestureRecognizerStateBegan;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    self.currentLocation = [touches.anyObject locationInView:self.view];
    self.moved = YES;
    self.state = UIGestureRecognizerStateChanged;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    self.currentLocation = [touches.anyObject locationInView:self.view];
    self.state = UIGestureRecognizerStateEnded;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.state = UIGestureRecognizerStateCancelled;
}

@end

@interface SGRLegacyTabBar : UITabBar <UITabBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *stockBar;
@property (nonatomic, copy) NSArray<UIView *> *sources;
// The tab set apart (Split tabs), on its own round button and not on the capsule: Spotify's view of it and the
// item that stands for it (never one of `items`), and whether its page is the open one, in which case the
// capsule has no selection.
@property (nonatomic, weak) UIView *apartSource;
@property (nonatomic, strong) UITabBarItem *apartItem;
@property (nonatomic) BOOL apartSelected;
@property (nonatomic, weak) UILongPressGestureRecognizer *hold;
@property (nonatomic, weak) UIGestureRecognizer *drag;
@property (nonatomic) BOOL holding;
// The last tab actually navigated to. Create is never this -- see isCreateSource -- so tapping/dragging
// onto Create can always snap the bar's selection (and the pill) straight back to this instead of
// resting on, or passing through, a "tab" that never really opened.
@property (nonatomic, weak) UITabBarItem *lastRealItem;
// Whichever tab was already selected when the current touch began. Tells dragged: on release whether
// the gesture actually crossed onto a different tab (a real switch, already animated live as it
// happened) or landed back on the one it started on (a tap, or a there-and-back drag) -- which gets an
// icon bump instead of ever moving the pill, because the pill has nothing to move for.
@property (nonatomic, weak) UITabBarItem *gestureStartItem;
// Which of Spotify's own tabs (the one whose label is painted white) was open the moment Create was
// tapped, and whether Create's menu is still to be seen off. Once it is gone, that tab against the one
// Spotify has open then says whether the menu took the user to another tab.
@property (nonatomic, weak) UIView *sourceBeforeCreate;
@property (nonatomic) BOOL awaitingCreateClose;
@end

static void syncBar(UIView *stockBar);
// Called only when Spotify's own navigation genuinely changed the selected controller from outside our
// bar (a link, the side drawer) -- see the TabBarContainerImpl hook below. Every other caller goes
// through plain syncBar, which trusts whatever tab our own tap/drag handling last confirmed
// (SGRLegacyTabBar.lastRealItem) over Spotify's isActive/label-color heuristic. That heuristic never
// clears for a tab the mod added itself: Spotify's own navigation stack never touched it, so the
// previously active *real* tab's label just stays white forever, and re-scanning it on every layout
// pass kept snapping the selection (and the pill) back to that old tab.
static void syncBarExternalChange(UIView *stockBar);
static void syncBarCore(UIView *stockBar, BOOL rescanSelection);
static void followCreateClose(UIView *stockBar);

#pragma mark - the compact bar's circles

// A round control of the compact bar: a glass circle with one tab's glyph on it. The glass is SGGlassFor's, so
// it is a legacy glass pane with Legacy Liquid Glass on and a plain blur without it, and comes and goes by its
// effect (SGRShowGlass), never by an alpha on the control, which UIKit draws a blur wrongly under. The control
// is scaled while it is away, so it grows in as the bar minimizes; its size and place are set by bounds and
// center, since a frame is undefined under a transform.
@interface SGRLegacyCircle : UIControl
@property (nonatomic, strong, readonly) UIImageView *glyph;
@property (nonatomic, copy) void (^onTap)(void);
// The tab the circle stands for, and whether that is Create.
@property (nonatomic, weak) UITabBarItem *item;
@property (nonatomic) BOOL holdsCreate;
// Shows or hides the circle; asked for inside an animation it moves in that animation.
- (void)setShown:(BOOL)shown;
// Create's menu open: the plus turns 45 degrees onto a white disc, as on the capsule's own Create button.
- (void)setCreateOpen:(BOOL)open;
@end

@implementation SGRLegacyCircle {
    UIView *_pane;
    UIView *_film;
    UIView *_disc;
    BOOL _shown, _configured, _open;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _pane = SGGlassFor(self, &kCirclePaneKey);
    _pane.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _film = SGRGlassFilm(self, &kCircleFilmKey, _pane, 0);
    _glyph = [UIImageView new];
    _glyph.userInteractionEnabled = NO;
    _glyph.contentMode = UIViewContentModeCenter;
    _glyph.tintColor = UIColor.whiteColor;
    [self addSubview:_glyph];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    // A true circle: the circular corner curve, not the continuous one the capsule's ends and the now playing
    // card have, which on a square draws a squircle.
    CGFloat radius = MIN(bounds.size.width, bounds.size.height) / 2;
    if (!CGRectEqualToRect(_pane.frame, bounds)) _pane.frame = bounds;
    SGShapeGlass(_pane, radius, YES);
    _pane.layer.cornerCurve = kCACornerCurveCircular;
    SGRGlassFilm(self, &kCircleFilmKey, _pane, radius).layer.cornerCurve = kCACornerCurveCircular;
    // bounds and center, not frame: the glyph is turned while Create's menu is up.
    _glyph.bounds = (CGRect){CGPointZero, bounds.size};
    _glyph.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    if (_disc) {
        CGFloat size = MIN(round(_glyph.image.size.height * 4.0 / 3.0), bounds.size.height - 8);
        _disc.bounds = CGRectMake(0, 0, size, size);
        _disc.layer.cornerRadius = size / 2;
        _disc.center = _glyph.center;
    }
}

- (void)setShown:(BOOL)shown {
    if (_configured && _shown == shown) return;
    _configured = YES;
    _shown = shown;
    SGRShowGlass(_pane, shown);
    _film.alpha = shown ? 1 : 0;
    _glyph.alpha = shown ? 1 : 0;
    self.transform = shown ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.6, 0.6);
    self.userInteractionEnabled = shown;
    if (!shown) [self setCreateOpen:NO];
}

- (void)setCreateOpen:(BOOL)open {
    if (_open == open || (open && !_shown)) return;
    _open = open;
    if (!_disc) {
        _disc = [[UIView alloc] initWithFrame:CGRectZero];
        _disc.userInteractionEnabled = NO;
        _disc.backgroundColor = UIColor.whiteColor;
        _disc.alpha = 0;
        _disc.transform = CGAffineTransformMakeScale(0.4, 0.4);
        [self insertSubview:_disc belowSubview:_glyph];
    }
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0
        options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self->_disc.alpha = open ? 1 : 0;
        self->_disc.transform = open ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.4, 0.4);
        self->_glyph.transform = open ? CGAffineTransformMakeRotation(M_PI_4) : CGAffineTransformIdentity;
        self->_glyph.tintColor = open ? UIColor.blackColor : UIColor.whiteColor;
    } completion:nil];
}

- (void)tapped {
    if (self.onTap) self.onTap();
}

@end

#pragma mark - reading Spotify's items

// The items the bar shows, left to right as Navbar/Navbar.x placed them.
static NSArray<UIView *> *tabItems(UIView *tabBar) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *item in SGRowIn(tabBar).arrangedSubviews) {
        if (!item.hidden && item.bounds.size.width >= 20) [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(SGFrameIn(a, tabBar).origin.x) compare:@(SGFrameIn(b, tabBar).origin.x)];
    }];
}

// The tab that stands on the round button of its own: the last one set apart. With nothing but split tabs the
// bar has one group and no tab is apart (Navbar.x), so then there is none.
static UIView *trailingSource(NSArray<UIView *> *items) {
    UIView *trail = nil;
    NSUInteger apartCount = 0;
    for (UIView *item in items) {
        if (!SGRTabIsApart(item)) continue;
        trail = item;
        apartCount++;
    }
    return apartCount >= items.count ? nil : trail;
}

// Navbar.x never reorders Spotify's row and appends the mod's own tabs after it, so Home stays first.
static BOOL isHome(UIView *item, UIView *tabBar) {
    return item && item == SGRowIn(tabBar).arrangedSubviews.firstObject;
}

// Create never pushes a screen -- tapping it only pops CreateMenu's own option list open over whatever
// is already on screen, and tapping anywhere dismisses that list again with nothing having navigated.
// So it must never become the bar's real "selected" tab: the pill parking on it, or drifting toward
// its slot, would be showing a screen that was never actually opened.
//
// The row's arranged subviews are Element's ElementContentView wrappers (trees/continuous/1.txt), and
// CreateMenuTabBarItemView is two levels down inside one -- never the arranged subview itself. A plain
// isKindOfClass: on the item was therefore always NO: Create counted as a real tab, the pill moved
// onto it, lastRealItem became Create and nothing ever moved the selection back once its popover was
// gone. So the item's whole subtree is searched, for the class and for Spotify's own id for it.
static BOOL isCreateSource(UIView *source) {
    if (!source) return NO;
    __block BOOL found = NO;
    SGForEachView(source, ^(UIView *v) {
        if (found) return;
        found = [NSStringFromClass(v.class) containsString:@"CreateMenuTabBarItemView"] || [v.accessibilityIdentifier isEqualToString:@"TabBar.Item.Create"];
    });
    return found;
}

static UILabel *labelIn(UIView *item) {
    __block UILabel *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = (UILabel *)v;
    });
    return label;
}

static UIView *iconIn(UIView *item) {
    __block UIView *icon = nil;
    SGForEachView(item, ^(UIView *v) {
        if (icon || v.bounds.size.width < 2) return;
        if ([v isKindOfClass:UIImageView.class] || [NSStringFromClass(v.class) containsString:@"IconView"]) icon = v;
    });
    return icon;
}

// Spotify paints the selected tab's label white and the rest #B3B3B3.
static BOOL isActive(UIView *item) {
    UIColor *color = labelIn(item).textColor;
    CGFloat white = 0, alpha = 0, r, g, b;
    if (![color getWhite:&white alpha:&alpha] && [color getRed:&r green:&g blue:&b alpha:&alpha]) white = MIN(r, MIN(g, b));
    return white > 0.95;
}

// The tab of Spotify's own whose page is really open: the one whose label is painted white, Create
// never counting. Nil when that tab is hidden from the bar.
static UIView *activeStockSource(UIView *stockBar) {
    for (UIView *item in tabItems(stockBar)) {
        if (!isCreateSource(item) && isActive(item)) return item;
    }
    return nil;
}

static BOOL hasInk(UIImage *image) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    if (!width || !height) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(context);
    const uint8_t *alpha = pixels.bytes;
    for (size_t i = 0; i < pixels.length; i++) if (alpha[i] > 16) return YES;
    return NO;
}

static UIImage *renderLayer(CALayer *layer, CGSize size) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [layer renderInContext:context.CGContext];
    }];
    return hasInk(image) ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

// The two pictures of a tab, outline and filled, taken from Spotify's own icon view the first time it
// has a size. UITabBar needs both up front, but Spotify's view only ever draws one of them. So isActive
// is flipped, the other state drawn, and isActive put back, all inside one runloop turn, so nothing
// reaches the screen. Without this the filled picture only turned up ~0.3 s after the first tap, once
// Spotify had repainted the view itself.
static void captureGlyphs(UIView *live, UITabBarItem *item) {
    if (![live respondsToSelector:@selector(isActive)] || ![live respondsToSelector:@selector(setIsActive:)]) return;
    SPTEncoreIconView *view = (SPTEncoreIconView *)live;
    CGSize size = live.bounds.size;
    BOOL was = [view isActive];
    UIImage *now = renderLayer(live.layer, size);
    [view setIsActive:!was];
    [view layoutIfNeeded];
    [live.layer displayIfNeeded];
    UIImage *other = renderLayer(live.layer, size);
    [view setIsActive:was];
    [view layoutIfNeeded];
    if (!now || !other || [UIImagePNGRepresentation(now) isEqualToData:UIImagePNGRepresentation(other)]) return;
    item.image = was ? other : now;
    item.selectedImage = was ? now : other;
    objc_setAssociatedObject(item, &kFilledLiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(item, &kOutlineLiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Both pictures of a tab. Create has no filled variant (the two states draw the same), so it keeps the
// picture Spotify's view shows, and takes a state's picture from the live view the first time it is
// seen in that state, the way it always did.
static void learnGlyphs(UIView *source, UITabBarItem *item) {
    UIView *live = iconIn(source);
    if (!live || live.bounds.size.width < 2) return;
    CGSize size = live.bounds.size;
    if (!item.image) item.image = renderLayer(live.layer, size);
    if (!item.selectedImage) item.selectedImage = renderLayer(live.layer, size);
    if (!objc_getAssociatedObject(item, &kGlyphsTakenKey)) {
        objc_setAssociatedObject(item, &kGlyphsTakenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        captureGlyphs(live, item);
    }
    BOOL active = [live respondsToSelector:@selector(isActive)] ? [(SPTEncoreIconView *)live isActive] : isActive(source);
    const void *key = active ? &kFilledLiveKey : &kOutlineLiveKey;
    if (objc_getAssociatedObject(item, key)) return;
    UIImage *seen = renderLayer(live.layer, size);
    if (!seen) return;
    objc_setAssociatedObject(item, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (active) item.selectedImage = seen; else item.image = seen;
}

#pragma mark - passing a tap on

// NavigationUI_TabBarImpl's TabBarItemElementUI answers a tap recognizer (-handleTap), so the tap is
// replayed through the recognizer's own target-action pairs, the same call a real touch ends in.
static BOOL fireTapRecognizers(UIView *view) {
    Ivar targetsIvar = class_getInstanceVariable(UIGestureRecognizer.class, "_targets");
    if (!targetsIvar) return NO;
    BOOL fired = NO;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:UITapGestureRecognizer.class] || !recognizer.enabled) continue;
        for (id pair in object_getIvar(recognizer, targetsIvar)) {
            Ivar targetIvar = class_getInstanceVariable([pair class], "_target");
            Ivar actionIvar = class_getInstanceVariable([pair class], "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(pair, targetIvar);
            SEL action = *(SEL *)((char *)(__bridge void *)pair + ivar_getOffset(actionIvar));
            if (!target || !action || ![target respondsToSelector:action]) continue;
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, recognizer);
            fired = YES;
        }
    }
    return fired;
}

static void forwardTap(UIView *item) {
    __block BOOL sent = NO;
    SGForEachView(item, ^(UIView *v) {
        if (!sent) sent = fireTapRecognizers(v);
    });
    SGForEachView(item, ^(UIView *v) {
        if (sent || ![v isKindOfClass:UIControl.class]) return;
        [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        sent = YES;
    });
}

// A tap (or a there-and-back drag) that ends back on the tab that was already open never moves the
// pill -- selectedItem never changed, there's nothing for it to move to -- but it should still feel
// like the tap registered. A small scale pulse on the icon itself stands in for that.
static void bumpIcon(UITabBar *bar, UITabBarItem *item) {
    if (!item) return;
    __block UIView *iconView = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (iconView || v.hidden || ![v isKindOfClass:UIImageView.class]) return;
        UIImage *image = ((UIImageView *)v).image;
        if (image && (image == item.image || image == item.selectedImage)) iconView = v;
    });
    if (!iconView) return;
    // One continuous keyframe timeline, not two animateWithDuration calls chained through a completion
    // handler: the ease-out scale-up and the separate spring scale-down have different velocity at the
    // instant they hand off, and that mismatch is what read as a jerk. A single keyframe animation has
    // no such seam.
    [UIView animateKeyframesWithDuration:0.26 delay:0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
        [UIView addKeyframeWithRelativeStartTime:0 relativeDuration:0.4 animations:^{
            iconView.transform = CGAffineTransformMakeScale(1.12, 1.12);
        }];
        [UIView addKeyframeWithRelativeStartTime:0.4 relativeDuration:0.6 animations:^{
            iconView.transform = CGAffineTransformIdentity;
        }];
    } completion:nil];
}

// UITabBar does not repaint an icon between its outline and filled bitmaps when the selection changes
// on this bar: the selected tab is drawn right after the tabs are rebuilt (hiding or moving one in Mod
// Settings) and never again after a tap. So the swap is not left to UIKit. Each item's glyph is drawn
// by an image view of ours laid over the one UIKit draws in the item's UITabBarButton, showing
// selectedImage (filled) on the selected item and image (outline) on the rest, and UIKit's own is
// hidden. Buttons are matched to items by their order across the bar. Run from the bar's layout pass
// and from the selection setter, so it follows both a resize and a tap or drag.
// setItems: can leave a UITabBarButton behind for an item that is gone (seen as a second, unplaced
// "Your Library" at the left of the bar after the tab list was rebuilt twice during launch). Every live
// item owns exactly one button -- UITabBarItem's "view" -- so any other UITabBarButton is a leftover.
// Only acts once every item has its button, so a bar still being built is never stripped.
static void pruneStrayButtons(UITabBar *bar) {
    NSMutableSet<UIView *> *owned = [NSMutableSet set];
    for (UITabBarItem *item in bar.items) {
        UIView *view = [item valueForKey:@"view"];
        if (view) [owned addObject:view];
    }
    if (!bar.items.count || owned.count != bar.items.count) return;
    for (UIView *v in [bar.subviews copy]) {
        if ([NSStringFromClass(v.class) isEqualToString:@"UITabBarButton"] && ![owned containsObject:v]) [v removeFromSuperview];
    }
}

static void paintGlyphs(UITabBar *bar) {
    NSArray<UITabBarItem *> *items = bar.items;
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    for (UIView *v in bar.subviews) {
        if ([NSStringFromClass(v.class) isEqualToString:@"UITabBarButton"]) [buttons addObject:v];
    }
    if (!items.count || buttons.count != items.count) return;
    [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(a.frame.origin.x) compare:@(b.frame.origin.x)];
    }];
    for (NSUInteger i = 0; i < items.count; i++) {
        UITabBarItem *item = items[i];
        UIView *button = buttons[i];
        UIImageView *overlay = objc_getAssociatedObject(button, &kGlyphOverlayKey);
        UIImageView *native = nil;
        for (UIView *v in button.subviews) {
            if (v != overlay && [v isKindOfClass:UIImageView.class] && v.bounds.size.width >= 2) { native = (UIImageView *)v; break; }
        }
        UIImage *want = (item == bar.selectedItem && item.selectedImage) ? item.selectedImage : item.image;
        if (!native || !want) {
            overlay.hidden = YES;
            continue;
        }
        if (!overlay) {
            overlay = [UIImageView new];
            overlay.userInteractionEnabled = NO;
            overlay.contentMode = UIViewContentModeCenter;
            overlay.tintColor = UIColor.whiteColor;
            objc_setAssociatedObject(button, &kGlyphOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (overlay.superview != button) [button addSubview:overlay];
        // bounds + center, not frame: the overlay of Create is rotated while its menu is up, and assigning
        // a frame to a transformed view scrambles it.
        CGRect nativeFrame = native.frame;
        CGPoint nativeCenter = CGPointMake(CGRectGetMidX(nativeFrame), CGRectGetMidY(nativeFrame));
        if (!CGSizeEqualToSize(overlay.bounds.size, nativeFrame.size)) overlay.bounds = (CGRect){CGPointZero, nativeFrame.size};
        if (!CGPointEqualToPoint(overlay.center, nativeCenter)) overlay.center = nativeCenter;
        if (overlay.image != want) overlay.image = want;
        overlay.hidden = NO;
        native.hidden = YES;
    }
}

// Spotify's own Create item turns its plus 45 degrees and puts a white disc behind it while the menu is
// open. That runs on the hidden stock view, so the glass bar has to do the same on its own Create button.
static void setCreateOpen(SGRLegacyTabBar *bar, BOOL open) {
    // Create on the apart tab's own button: that button does it, and the capsule has no Create.
    if (bar.apartSource && isCreateSource(bar.apartSource)) {
        UIView *stock = bar.stockBar;
        UIView *barHost = stock ? objc_getAssociatedObject(stock, &kHostKey) : nil;
        SGRLegacyCircle *trail = barHost ? objc_getAssociatedObject(barHost, &kTrailKey) : nil;
        [trail setCreateOpen:open];
        return;
    }
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < bar.sources.count; i++) {
        if (isCreateSource(bar.sources[i])) { index = i; break; }
    }
    if (index == NSNotFound || index >= bar.items.count) return;
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    for (UIView *v in bar.subviews) {
        if ([NSStringFromClass(v.class) isEqualToString:@"UITabBarButton"]) [buttons addObject:v];
    }
    if (buttons.count != bar.items.count) return;
    [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(a.frame.origin.x) compare:@(b.frame.origin.x)];
    }];
    UIView *button = buttons[index];
    UIImageView *overlay = objc_getAssociatedObject(button, &kGlyphOverlayKey);
    if (!overlay) return;
    UIView *disc = objc_getAssociatedObject(button, &kCreateDiscKey);
    if (!disc) {
        disc = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
        disc.userInteractionEnabled = NO;
        disc.backgroundColor = UIColor.whiteColor;
        disc.layer.cornerRadius = 20;
        disc.alpha = 0;
        objc_setAssociatedObject(button, &kCreateDiscKey, disc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (disc.superview != button) [button insertSubview:disc belowSubview:overlay];
    // Sized from the icon it sits behind (a third bigger), so it stays inside the pill with or without labels.
    CGFloat discSize = round(overlay.bounds.size.height * 4.0 / 3.0);
    if (fabs(disc.bounds.size.width - discSize) > 0.5) {
        disc.bounds = CGRectMake(0, 0, discSize, discSize);
        disc.layer.cornerRadius = discSize / 2;
    }
    disc.center = overlay.center;
    if ((disc.alpha > 0.5) == open && (open || CGAffineTransformIsIdentity(overlay.transform))) return;
    if (open) disc.transform = CGAffineTransformMakeScale(0.4, 0.4);
    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0
        options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        disc.alpha = open ? 1 : 0;
        disc.transform = open ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.4, 0.4);
        overlay.transform = open ? CGAffineTransformMakeRotation(M_PI_4) : CGAffineTransformIdentity;
        overlay.tintColor = open ? UIColor.blackColor : UIColor.whiteColor;
    } completion:nil];
}

#pragma mark - the system bar

@implementation SGRLegacyTabBar

- (void)layoutSubviews {
    [super layoutSubviews];
    pruneStrayButtons(self);
    paintGlyphs(self);
    // On the first taps after launch the pill was placed while the buttons were not yet where UIKit
    // finally puts them, and nothing placed it again. Every layout pass re-checks it against the buttons.
    UIView *stock = self.stockBar;
    UIView *host = stock ? objc_getAssociatedObject(stock, &kHostKey) : nil;
    UIView *pill = host ? objc_getAssociatedObject(host, &kSelPillKey) : nil;
    CGFloat centerX = pill && !pill.hidden ? [self renderedCenterXForItem:self.selectedItem] : NAN;
    if (!isnan(centerX) && pill.frame.size.width > 0) {
        CGFloat wantX = self.frame.origin.x + centerX - pill.frame.size.width / 2;
        if (fabs(pill.frame.origin.x - wantX) > 0.5) {
            [UIView animateWithDuration:0.25 delay:0
                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                animations:^{ CGRect f = pill.frame; f.origin.x = wantX; pill.frame = f; } completion:nil];
        }
    }
}

- (void)setSelectedItem:(UITabBarItem *)item {
    if (item) self.apartSelected = NO;
    [super setSelectedItem:item];
    paintGlyphs(self);
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    NSUInteger index = [self.items indexOfObject:item];
    if (index == NSNotFound || index >= self.sources.count) return;
    UIView *source = self.sources[index];
    if (isCreateSource(source)) {
        // Just pops the menu open -- never a real navigation. The pill goes to Create while the menu is
        // up (lastRealItem is left alone, so it knows where to come back to), and returns to the tab
        // that was open once the menu is gone.
        UIView *stockBar = self.stockBar;
        self.sourceBeforeCreate = stockBar ? activeStockSource(stockBar) : nil;
        forwardTap(source);
        // The apart tab stays the open one while Create's menu is up over it.
        BOOL apartSelected = self.apartSelected;
        self.selectedItem = item;
        self.apartSelected = apartSelected;
        setCreateOpen(self, YES);
        if (stockBar) {
            followCreateClose(stockBar);
            syncBar(stockBar);
        }
        // UIKit's own internal touch handling can still win a race and snap selectedItem back to
        // whatever it had before, on the very next runloop turn, if our gesture recognizer's
        // cancelsTouchesInView didn't fully suppress it in time -- re-assert once more a beat later,
        // after that would have already happened, so the pill doesn't silently lose the tug of war.
        __weak typeof(self) weakSelf = self;
        __weak UIView *weakStock = stockBar;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            UIView *stock = weakStock;
            if (!strongSelf || !stock) return;
            if (strongSelf.selectedItem != item) {
                strongSelf.selectedItem = item;
                syncBar(stock);
            }
        });
        return;
    }
    self.lastRealItem = item;
    // Home tapped while on Home pops Spotify's stack, which would take Mod Settings straight off it.
    if (!self.holding) forwardTap(source);
    // Spotify repaints its labels a moment later; a tap it did not take snaps the selection back.
    UIView *stockBar = self.stockBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (stockBar) syncBar(stockBar);
    });
}

// The apart tab's round button tapped, as the capsule's own tap would be: Create pops its menu, any other tab is
// opened and the capsule gives up its selection.
- (void)tapApart {
    UIView *source = self.apartSource;
    UIView *stockBar = self.stockBar;
    if (!source) return;
    if (isCreateSource(source)) {
        self.sourceBeforeCreate = stockBar ? activeStockSource(stockBar) : nil;
        forwardTap(source);
        setCreateOpen(self, YES);
        if (stockBar) followCreateClose(stockBar);
        return;
    }
    self.apartSelected = YES;
    self.selectedItem = nil;
    forwardTap(source);
    if (!stockBar) return;
    syncBar(stockBar);
    // Spotify repaints its labels a moment later.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        syncBar(stockBar);
    });
}

// UIKit's item views are private, so the item under a touch is the one whose title label or glyph is
// nearest. With the labels hidden only the glyph is left; UIKit shows the item's own image instance.
- (UITabBarItem *)itemAt:(CGPoint)point {
    __block UITabBarItem *nearest = nil;
    __block CGFloat best = CGFLOAT_MAX;
    SGForEachView(self, ^(UIView *v) {
        BOOL label = [v isKindOfClass:UILabel.class], glyph = [v isKindOfClass:UIImageView.class];
        if ((!label && !glyph) || v.bounds.size.width < 1) return;
        CGFloat distance = fabs([v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), 0) toView:self].x - point.x);
        if (distance >= best) return;
        for (UITabBarItem *item in self.items) {
            UIImage *image = glyph ? ((UIImageView *)v).image : nil;
            if (label ? ![((UILabel *)v).text isEqualToString:item.title] : !image || (image != item.image && image != item.selectedImage)) continue;
            best = distance;
            nearest = item;
            break;
        }
    });
    return nearest;
}

// The item's true on-screen x-center -- reading the actual rendered icon/label frame, the same way
// itemAt: matches a touch point to an item, just run in reverse (item known, frame wanted). Used
// instead of an assumed kNavItemWidth/kNavItemSpacing formula: UIKit's own centered fixed-width layout
// doesn't line up with that formula pt for pt, and the gap compounds with every index -- why the pill
// used to drift further right the further right the tab was, and rode straight past the last one.
// NAN when the item's own views aren't in the hierarchy yet (still loading, or a stale item).
- (CGFloat)renderedCenterXForItem:(UITabBarItem *)item {
    if (!item) return NAN;
    NSUInteger index = [self.items indexOfObject:item];
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    for (UIView *v in self.subviews) {
        if ([NSStringFromClass(v.class) isEqualToString:@"UITabBarButton"]) [buttons addObject:v];
    }
    if (index != NSNotFound && buttons.count == self.items.count && buttons.count) {
        [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            return [@(a.frame.origin.x) compare:@(b.frame.origin.x)];
        }];
        if (buttons[index].bounds.size.width > 1) return CGRectGetMidX(buttons[index].frame);
    }
    __block CGRect unionFrame = CGRectNull;
    SGForEachView(self, ^(UIView *v) {
        BOOL label = [v isKindOfClass:UILabel.class], glyph = [v isKindOfClass:UIImageView.class];
        if ((!label && !glyph) || v.bounds.size.width < 1) return;
        if (glyph) {
            UIImage *image = ((UIImageView *)v).image;
            if (!image || (image != item.image && image != item.selectedImage)) return;
        } else if (!item.title.length || ![((UILabel *)v).text isEqualToString:item.title]) {
            return;
        }
        CGRect frame = [v convertRect:v.bounds toView:self];
        unionFrame = CGRectIsNull(unionFrame) ? frame : CGRectUnion(unionFrame, frame);
    });
    return CGRectIsNull(unionFrame) ? NAN : CGRectGetMidX(unionFrame);
}

// UIView asks itself this for its own recognizers too, so only the hold is answered here.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != self.hold) return [super gestureRecognizerShouldBegin:recognizer];
    NSUInteger index = [self.items indexOfObject:[self itemAt:[recognizer locationInView:self]]];
    return index < self.sources.count && isHome(self.sources[index], self.stockBar);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) {
        self.holding = YES;
        SGOpenModSettings(self);
    } else if (hold.state != UIGestureRecognizerStateChanged) {
        // The bar may still pick Home as the finger lifts, after this.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.holding = NO;
        });
    }
}

// Resolves to whichever tab is nearest at every touch update, never a position in between: crossing
// into a new tab's territory snaps the pill there immediately with one smooth animation, and release
// decides which tab it lands on and actually switches Spotify's content -- the same call a plain tap
// would have made through the delegate method.
- (void)dragged:(SGRLegacyTabDragRecognizer *)g {
    UIView *stockBar = self.stockBar;
    UITabBarItem *item = [self itemAt:g.currentLocation];
    NSUInteger itemIndex = item ? [self.items indexOfObject:item] : NSNotFound;
    BOOL itemIsCreate = itemIndex != NSNotFound && itemIndex < self.sources.count && isCreateSource(self.sources[itemIndex]);

    if (g.state == UIGestureRecognizerStateBegan) {
        self.gestureStartItem = self.selectedItem;
    }

    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        // Setting selectedItem alone does not make our own overlay bar relay out -- nothing hooks that
        // property -- so without calling syncBar right here, the pill only actually moved once some
        // unrelated Spotify UI event happened to trigger it later (typically only after the real
        // navigation completed on release), which read as the pill starting its slide late, once the new
        // tab's content was already on screen. Calling syncBar directly here moves it the instant WE
        // decide the selection changed.
        if (item && !itemIsCreate && item != self.selectedItem) {
            self.selectedItem = item;
            if (stockBar) syncBar(stockBar);
        }
    } else if (g.state == UIGestureRecognizerStateEnded) {
        if (item) {
            if (!itemIsCreate && item != self.selectedItem) {
                self.selectedItem = item;
                if (stockBar) syncBar(stockBar);
            }
            [self tabBar:self didSelectItem:item];
            // Ended on the same tab the touch started on -- give the icon a bump instead, since the
            // pill genuinely never moved (selectedItem never changed).
            if (item == self.gestureStartItem) bumpIcon(self, item);
        } else if (stockBar) {
            syncBar(stockBar);
        }
        self.gestureStartItem = nil;
    } else if (g.state == UIGestureRecognizerStateCancelled) {
        if (stockBar) syncBar(stockBar);
        self.gestureStartItem = nil;
    }
}

@end

// The system bar's own view in Spotify's bar. UIKit measures the system bar and lays it out by the safe
// area of the view it stands in, and the room made under Spotify's bar is not the phone's: on a phone
// with a home button it went under the platter as well, squeezing it to 49 pt. So this view hands the
// bar the safe area without the room.
@interface SGRLegacyTabBarHost : UIView
@end

@implementation SGRLegacyTabBarHost
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = [super safeAreaInsets];
    // The host's own frame now stands kNavGlassBottomMargin above the screen's real safe area, which
    // hands it that much *extra* raw inset on its own. Left alone, UITabBar would read that as more
    // home-indicator padding to reserve and push the icon/label stack up, off-centre in the pill.
    // Canceling it out here keeps the bar's internal vertical centering exactly as it was undocked.
    insets.bottom = MAX(0, insets.bottom - sg_room - kNavGlassBottomMargin);
    return insets;
}

// Minimized, the host still spans the screen, and its bare part between the circles is where the now playing
// card stands: a touch there goes on to the card instead of stopping here.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return sg_minimized && hit == self ? nil : hit;
}
@end

@interface SGRLegacyHomeHold : UILongPressGestureRecognizer
@end

@implementation SGRLegacyHomeHold
+ (void)held:(SGRLegacyHomeHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) SGOpenModSettings(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so Home is not tapped too.
static void holdHome(UIView *stockBar) {
    UIView *home = SGRowIn(stockBar).arrangedSubviews.firstObject;
    if (!home) return;
    for (UIGestureRecognizer *recognizer in home.gestureRecognizers) {
        if ([recognizer isKindOfClass:SGRLegacyHomeHold.class]) return;
    }
    [home addGestureRecognizer:[[SGRLegacyHomeHold alloc] initWithTarget:SGRLegacyHomeHold.class action:@selector(held:)]];
}

#pragma mark - room for the glass bar

// UIKit's glass bar asks for 83 pt, the platter the top 62 of it, over no more safe area than a Face ID
// phone's 34 (simulator, iOS 26.5 and 27). Spotify's bar is its 49 pt row over the bottom safe area of
// TabBarContainerImpl's view: a guide from 49 pt above the safe area's bottom to the view's bottom sets
// its height (its viewDidLoad, 0x100840a2c), the now playing bar stands on that guide's top
// (MainUIContainer's chrome bottom anchor, 0x100ae0178), the bar slides away by the inset plus 49 when
// Spotify hides it (0x1037169a4) and the pages get 49 on top of the inset (0x10707bde4). A Face ID
// phone gives the view 34 and the two bars match. A phone with a home button gives it none, and so does
// Spotify's message bar (LimitedExperienceIndicatorBar: Offline, Private Session) coming in under the
// tab bar, which takes the home indicator's inset for itself: the glass bar stood 34 pt above
// Spotify's, over the now playing bar. So the view gets the rest of the glass bar's height as safe
// area, and Spotify lays its bar, the now playing bar, the pages and the hide out for the glass bar
// itself, and moves them all with the message bar.
static const CGFloat kStockRow = 49;

// UIKit asks for 62 + max(21, inset) on a phone with a home button, max(83, 49 + inset) on a Face ID
// phone, by the safe area of the view the bar stands in. SGRLegacyTabBarHost keeps the room out of that; if
// it ever reached the bar again, the bar would ask for more room every pass, so what it asks for with
// no room made is what is kept.
static CGFloat glassHeight(UITabBar *bar, UIView *stockBar) {
    if (sg_room < 0.5 || sg_glassHeight <= 0) sg_glassHeight = [bar sizeThatFits:CGSizeMake(stockBar.bounds.size.width, kStockRow)].height;
    return sg_glassHeight;
}

static UIViewController *containerOf(UIView *stockBar) {
    Class containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    for (UIResponder *r = stockBar.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:containerClass]) return (UIViewController *)r;
    }
    return nil;
}

static void makeRoom(UIViewController *container) {
    UIView *stockBar = sg_stockBar;
    UITabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (!bar.window || !container.isViewLoaded || ![stockBar isDescendantOfView:container.view]) return;
    UIEdgeInsets extra = container.additionalSafeAreaInsets;
    CGFloat inset = container.view.safeAreaInsets.bottom - extra.bottom;
    CGFloat height = glassHeight(bar, stockBar);
    // Spotify's regular width bar is a fixed 76 pt that ignores the inset.
    BOOL compact = container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    CGFloat room = compact ? MAX(0, ceil(height - kStockRow - inset)) : 0;
    if (fabs(extra.bottom - room) < 0.5) return;
    sg_room = extra.bottom = room;
    container.additionalSafeAreaInsets = extra;
}

// Create's menu closing is not announced to the bar: Create pushes nothing, so no selection event
// follows it. This polls for the menu to be gone, then puts the selection where the page that is
// really open says it belongs:
//  - Spotify itself went to another tab while the menu was up (something picked in it opened a page
//    there): the bar follows Spotify, as for a link.
//  - Otherwise nothing moved, and the selection goes back to the tab the user was on, which may be a
//    tab of the mod's own that Spotify's labels know nothing about.
// A second look follows shortly after, since Spotify repaints its labels a moment after the change.
// Matched loosely (contains, not exact-equal, and checked by class name too) on purpose: the sheet's
// accessibilityIdentifier is read off a live view captured once by hand (trees/continuous/4.txt) and a
// future Spotify build, an A/B flag, or a slightly different presentation path (from Search's "+" or a
// long-press instead of the tab) could dress the same menu up under a different id, or leave it unset
// altogether. Falling through to the class name and to "is anything at all presented over us" keeps
// this from silently never firing again the way one exact string compare would.
static BOOL createMenuIsUp(UIView *stockBar) {
    __block BOOL up = NO;
    SGForEachView(stockBar.window ?: stockBar, ^(UIView *v) {
        if (up) return;
        if ([v.accessibilityIdentifier isEqualToString:@"CreateMenu"]) up = YES;
        else if ([NSStringFromClass(v.class) containsString:@"CreateMenuView"]) up = YES;
    });
    if (!up) up = containerOf(stockBar).presentedViewController != nil;
    return up;
}

static void settleAfterCreate(UIView *stockBar) {
    SGRLegacyTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar) return;
    setCreateOpen(bar, NO);
    UIView *open = activeStockSource(stockBar);
    if (open && open != bar.sourceBeforeCreate) {
        // The menu took Spotify to another tab: that brings the full bar back, as any other tab does.
        SGRLegacySetTabBarMinimized(NO, YES);
        syncBarExternalChange(stockBar);
        return;
    }
    UITabBarItem *back = bar.apartSelected ? nil : bar.lastRealItem;
    if ((back || bar.apartSelected) && bar.selectedItem != back) bar.selectedItem = back;
    syncBar(stockBar);
}

// `seen`: the menu has been up at least once. The first look can come before it has appeared, so it
// is waited for a little (ten looks, ~0.8 s) before the menu is taken to be gone; once seen, 560 looks
// (~45 s) at most, then it is settled anyway rather than watched forever.
// Polled every 0.08 s (was 0.3 s): the visible lag between the popover actually closing and the pill
// coming back is bounded by this interval plus the settle-again delay below, and 0.3 s of it read as a
// sluggish return on a real device. 0.08 s is fast enough to feel immediate without spamming the main
// thread noticeably -- createMenuIsUp is a view-tree walk, not a layout pass.
static void pollCreateClose(UIView *stockBar, NSUInteger attempt, BOOL seen) {
    __weak UIView *weakStock = stockBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *stock = weakStock;
        SGRLegacyTabBar *bar = stock ? objc_getAssociatedObject(stock, &kBarKey) : nil;
        if (!bar || !bar.awaitingCreateClose) return;
        BOOL up = createMenuIsUp(stock);
        if (up ? attempt < 560 : (!seen && attempt < 10)) {
            pollCreateClose(stock, attempt + 1, seen || up);
            return;
        }
        bar.awaitingCreateClose = NO;
        settleAfterCreate(stock);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *again = weakStock;
            if (again) settleAfterCreate(again);
        });
    });
}

static void followCreateClose(UIView *stockBar) {
    SGRLegacyTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar || bar.awaitingCreateClose) return;
    bar.awaitingCreateClose = YES;
    pollCreateClose(stockBar, 0, NO);
}

#pragma mark - compact

// A page scrolled down minimizes the bar (TabBarMinimize.x), the way the Music app's does and the way TabBar.x's
// does on iOS 26: the capsule gives way to a circle at the leading end holding the tab that is open, which
// brings the whole bar back, and to a circle at the trailing end holding the last tab set apart (Split tabs),
// when there is one, and the now playing card takes the room between them (NowPlayingBar.x asks
// SGRLegacyTabBarInlineSlot for it). Without a split tab the card runs on to the margin.
//
// The system bar underneath is not rebuilt: it keeps its items, goes clear and takes no touches, so the full
// bar is back as it was, selection and all. The circles are controls of the host with a glass pane of their
// own (SGRLegacyCircle), the capsule's glass goes by its effect, and all of it moves in the one SGRMotionBar
// spring that moves the card. The panes come from SGGlassFor, so this is the same for a plain blur and for
// legacy glass.

// Whether `item` can stand on the leading circle: a real tab of the capsule, not Create.
static BOOL leadsCompact(SGRLegacyTabBar *bar, UITabBarItem *item) {
    NSUInteger index = item ? [bar.items indexOfObject:item] : NSNotFound;
    return index < bar.sources.count && !isCreateSource(bar.sources[index]);
}

// A circle's tab, tapped the way the bar's own tap would: Create pops its menu, the rest are picked and passed
// on to Spotify. A tab that was already open just gets the tap (Home scrolls to its top); another one brings the
// full bar back (the hook on setSelectedViewController). The leading circle never brings it back by itself:
// only a scroll up does.
static void tapItem(UIView *stockBar, UITabBarItem *item) {
    SGRLegacyTabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    NSUInteger index = item ? [bar.items indexOfObject:item] : NSNotFound;
    if (index >= bar.sources.count) return;
    if (!isCreateSource(bar.sources[index])) bar.selectedItem = item;
    [bar tabBar:bar didSelectItem:item];
}

static SGRLegacyCircle *makeCircle(UIView *host, const void *key) {
    SGRLegacyCircle *circle = (SGRLegacyCircle *)SGLazyChild(host, key, ^UIView *{ return [SGRLegacyCircle new]; });
    // Made away, so it comes in with the bar's motion rather than being there at once.
    [UIView performWithoutAnimation:^{
        [host addSubview:circle];
        [circle setShown:NO];
    }];
    return circle;
}

static void placeCircle(SGRLegacyCircle *circle, CGRect frame, UIView *host) {
    if (!circle || CGRectIsEmpty(frame)) return;
    if (circle.superview != host) [host addSubview:circle];
    CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    if (!CGSizeEqualToSize(circle.bounds.size, frame.size)) circle.bounds = (CGRect){CGPointZero, frame.size};
    if (!CGPointEqualToPoint(circle.center, center)) circle.center = center;
    [circle layoutIfNeeded];
}

// Lays the bar out for the state it is in, called from every pass of syncBarCore with the capsule's frame and
// the frame the apart tab's round button has beside it: the capsule, its film, the selection pill and the system
// bar for the full bar, the leading circle for the compact one. The apart tab's button is there in both, and
// moves between the two places. Inside an animation the change moves in it.
static void placeCompact(UIView *stockBar, SGRLegacyTabBar *bar, UIView *host, NSArray<UIView *> *sources, CGRect platter, CGRect apartFrame,
                         UIView *navGlass, UIView *navTint, UIView *selPill) {
    UIView *trailSource = bar.apartSource;
    UITabBarItem *trailItem = bar.apartItem;
    // One tab has nothing to shrink to: the capsule's tabs and the apart one make two at least.
    BOOL compact = sg_minimized && sources.count + (trailSource ? 1 : 0) >= 2;

    // As tall as the now playing card beside them, round, and centered on the capsule's row.
    CGRect card = SGRNowPlayingCardFrameIn(host, NULL);
    CGFloat side = MIN(CGRectIsNull(card) ? kNavCircleSide : card.size.height, platter.size.height);
    CGFloat circleY = platter.origin.y + (platter.size.height - side) / 2;
    sg_leadFrame = CGRectMake(kNavGlassMargin, circleY, side, side);
    if (!trailSource) sg_trailFrame = CGRectZero;
    else if (compact) sg_trailFrame = CGRectMake(CGRectGetWidth(host.bounds) - kNavGlassMargin - side, circleY, side, side);
    else sg_trailFrame = apartFrame;

    UITabBarItem *leadItem = leadsCompact(bar, bar.selectedItem) ? bar.selectedItem : nil;
    if (!leadItem && leadsCompact(bar, bar.lastRealItem)) leadItem = bar.lastRealItem;
    if (!leadItem) {
        for (UITabBarItem *item in bar.items) {
            if (leadsCompact(bar, item)) {
                leadItem = item;
                break;
            }
        }
    }
    // Filled where the tab is open; on the apart button when that tab is, and then not on the leading one.
    BOOL trailSelected = trailSource && bar.apartSelected && !isCreateSource(trailSource);
    UIImage *leadImage = leadItem ? (!trailSelected && leadItem.selectedImage ? leadItem.selectedImage : leadItem.image) : nil;
    UIImage *trailImage = trailItem ? (trailSelected && trailItem.selectedImage ? trailItem.selectedImage : trailItem.image) : nil;

    SGRLegacyCircle *lead = objc_getAssociatedObject(host, &kLeadKey);
    SGRLegacyCircle *trail = objc_getAssociatedObject(host, &kTrailKey);
    if (compact && !lead) lead = makeCircle(host, &kLeadKey);
    if (trailSource && !trail) trail = makeCircle(host, &kTrailKey);
    [UIView performWithoutAnimation:^{
        placeCircle(lead, sg_leadFrame, host);
    }];
    // The apart button is on screen in both states, so on its first pass it is put in place without a
    // motion, and after that it moves.
    if (trail && trail.bounds.size.width < 1) {
        [UIView performWithoutAnimation:^{ placeCircle(trail, sg_trailFrame, host); }];
    } else {
        placeCircle(trail, sg_trailFrame, host);
    }
    NSUInteger leadIndex = leadItem ? [bar.items indexOfObject:leadItem] : NSNotFound;
    __weak UIView *weakStock = stockBar;
    if (lead) {
        if (lead.glyph.image != leadImage) lead.glyph.image = leadImage;
        lead.item = leadItem;
        lead.accessibilityLabel = leadIndex < sources.count ? labelIn(sources[leadIndex]).text : nil;
        if (!lead.onTap) {
            __weak SGRLegacyCircle *weakLead = lead;
            lead.onTap = ^{ tapItem(weakStock, weakLead.item); };
        }
    }
    if (trail) {
        if (trail.glyph.image != trailImage) trail.glyph.image = trailImage;
        trail.item = trailItem;
        trail.holdsCreate = trailSource && isCreateSource(trailSource);
        if (!trail.holdsCreate) [trail setCreateOpen:NO];
        trail.accessibilityLabel = trailSource ? labelIn(trailSource).text : nil;
        if (!trail.onTap) {
            trail.onTap = ^{
                UIView *stock = weakStock;
                SGRLegacyTabBar *legacy = stock ? objc_getAssociatedObject(stock, &kBarKey) : nil;
                [legacy tapApart];
            };
        }
    }

    [lead setShown:compact];
    [trail setShown:trailSource != nil];
    SGRShowGlass(navGlass, !compact);
    navTint.alpha = compact ? 0 : 1;
    selPill.alpha = compact ? 0 : 1;
    bar.alpha = compact ? 0 : 1;
    bar.userInteractionEnabled = !compact;
}

static void setMinimized(BOOL minimized, BOOL animated) {
    UIView *stockBar = sg_stockBar;
    if (minimized == sg_minimized) return;
    // Spotify's regular width bar is not this bar's row of tabs; it stays as it is. One tab has nothing to
    // shrink to.
    if (minimized && (!stockBar.window || stockBar.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact || tabItems(stockBar).count < 2)) return;
    sg_minimized = minimized;
    if (!stockBar) return;
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);
    animated &= host.window != nil;
    void (^apply)(void) = ^{
        syncBar(stockBar);
        [host layoutIfNeeded];
        SGRNowPlayingBarFollowTabBar();
    };
    if (!animated) {
        [UIView performWithoutAnimation:apply];
        return;
    }
    SGRAnimate(SGRMotionBar, apply, nil);
}

BOOL SGRLegacyTabBarMinimized(void) {
    return sg_minimized;
}

// The scroll asks from inside -[UIScrollView setContentOffset:], which Spotify can call inside an animation of
// its own, and the spring would then take that animation's length (TabBar.x, "minimized"). So a change asked for
// inside one is made on the main queue's next turn, outside it, and only if nothing was asked for since; one asked
// for outside any is made at once, and one with no animation stays at once too.
static NSUInteger sg_request;

void SGRLegacySetTabBarMinimized(BOOL minimized, BOOL animated) {
    NSUInteger request = ++sg_request;
    if (!animated) {
        [UIView performWithoutAnimation:^{ setMinimized(minimized, NO); }];
        return;
    }
    if (UIView.areAnimationsEnabled && UIView.inheritedAnimationDuration <= 0) {
        setMinimized(minimized, YES);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (request == sg_request) setMinimized(minimized, YES);
    });
}

CGRect SGRLegacyTabBarInlineSlot(UIView *host, CGFloat height) {
    UIView *stockBar = sg_stockBar;
    UIView *barHost = stockBar ? objc_getAssociatedObject(stockBar, &kHostKey) : nil;
    UIView *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (!sg_minimized || !host || !barHost || !bar.window || stockBar.hidden || stockBar.alpha < 0.01 || CGRectIsEmpty(sg_leadFrame)) return CGRectNull;
    // The circles' places, not what is on screen mid-spring.
    CGRect lead = [barHost convertRect:sg_leadFrame toView:host];
    CGFloat left = CGRectGetMaxX(lead) + SGRGrid;
    CGFloat right;
    if (!CGRectIsEmpty(sg_trailFrame)) {
        right = CGRectGetMinX([barHost convertRect:sg_trailFrame toView:host]) - SGRGrid;
    } else {
        CGRect whole = [stockBar convertRect:stockBar.bounds toView:host];
        right = CGRectGetMaxX(whole) - kNavGlassMargin;
    }
    CGRect slot = CGRectMake(left, CGRectGetMidY(lead) - height / 2, right - left, height);
    // A bar Spotify has slid away for a page takes the slot off the screen with it.
    CGRect inWindow = [host convertRect:slot toView:nil];
    if (slot.size.width < 100 || CGRectGetMaxY(inWindow) > CGRectGetMaxY(bar.window.bounds)) return CGRectNull;
    return slot;
}

static void syncBar(UIView *stockBar) {
    syncBarCore(stockBar, NO);
}

static void syncBarExternalChange(UIView *stockBar) {
    syncBarCore(stockBar, YES);
}

static void syncBarCore(UIView *stockBar, BOOL rescanSelection) {
    sg_stockBar = stockBar;

    SGRLegacyTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar) {
        bar = [[SGRLegacyTabBar alloc] initWithFrame:stockBar.bounds];
        // UIKit draws the glass in the appearance the bar inherits, and the bar is outside the navigation
        // stacks Spotify makes dark itself (-[SPNavigationController viewDidLoad] while +[SPTLiquidGlass
        // isEnabled]), so a phone in light mode had it light over Spotify's black. Spotify is dark whatever
        // the system is, and so is the bar.
        bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        // UITabBar's own chrome would sit in front of navGlass (below) and hide it: the glass is the bar's
        // only background.
        bar.backgroundColor = UIColor.clearColor;
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithTransparentBackground];
        // White icons and titles in every state, on the appearance itself: once a bar has one, its
        // per-state colours are what UIKit paints with, and tintColor alone would not decide them.
        for (UITabBarItemAppearance *layout in @[appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance]) {
            for (UITabBarItemStateAppearance *state in @[layout.normal, layout.selected]) {
                state.iconColor = UIColor.whiteColor;
                state.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
            }
        }
        bar.standardAppearance = appearance;
        bar.scrollEdgeAppearance = appearance;
        bar.delegate = bar;
        bar.stockBar = stockBar;
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:bar action:@selector(held:)];
        hold.delegate = bar;
        [bar addGestureRecognizer:hold];
        bar.hold = hold;
        // Telegram's own drag-to-switch, not an approximation of it anymore: SGRLegacyTabDragRecognizer above
        // is TabSelectionRecognizer.swift ported directly.
        SGRLegacyTabDragRecognizer *drag = [[SGRLegacyTabDragRecognizer alloc] initWithTarget:bar action:@selector(dragged:)];
        drag.delegate = bar;
        [bar addGestureRecognizer:drag];
        bar.drag = drag;
        objc_setAssociatedObject(stockBar, &kBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRLegacyTabBarHost *host = [SGRLegacyTabBarHost new];
        [host addSubview:bar];
        objc_setAssociatedObject(stockBar, &kHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The active tab is told apart by its filled glyph and the selection pill, not by the accent colour.
    bar.tintColor = UIColor.whiteColor;
    // UIKit's own default unselected tint (a mid grey in dark mode) is what made the three inactive
    // icons read as grey instead of white, next to the reference screenshot's fully white inactive
    // icons. renderLayer makes every icon an always-template image, so tint color is the only thing
    // that decides what color they actually draw in.
    bar.unselectedItemTintColor = UIColor.whiteColor;
    // Centered + a fixed narrow itemWidth, not .automatic's fill-the-frame stretch: three tabs used to
    // spread edge to edge across whatever width the bar was given, which is the "solid navbar" layout
    // this pill was never meant to inherit. With a fixed width UIKit centers the group instead of
    // stretching it, and the visible capsule below is sized to match that group, not the screen.
    bar.itemPositioning = UITabBarItemPositioningCentered;
    // itemWidth is set below, once sources.count is known -- with few tabs it stays the full
    // kNavItemWidth; past however many would overflow the platter's own max width, each slot narrows
    // just enough for all of them to still fit at that same width.
    bar.itemSpacing = kNavItemSpacing;
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);

    for (UIView *sub in stockBar.subviews) {
        if (sub == host) continue;
        sub.alpha = 0;
        sub.userInteractionEnabled = NO;
    }
    stockBar.superview.layer.backgroundColor = NULL;

    NSArray<UIView *> *allSources = tabItems(stockBar);
    if (!allSources.count) return;
    // The apart tab is on a button of its own, so the capsule holds the others.
    UIView *apartSource = trailingSource(allSources);
    NSMutableArray<UIView *> *capsuleSources = [allSources mutableCopy];
    if (apartSource) [capsuleSources removeObject:apartSource];
    NSArray<UIView *> *sources = capsuleSources;
    if (apartSource != bar.apartSource || (apartSource && !bar.apartItem)) {
        bar.apartSource = apartSource;
        bar.apartItem = apartSource ? [[UITabBarItem alloc] initWithTitle:labelIn(apartSource).text image:nil tag:-1] : nil;
        if (!apartSource) bar.apartSelected = NO;
    }
    // An item with no title is drawn by UIKit as its glyph alone, centred, on a bar of the same height.
    BOOL hideLabels = SGHidden(SGRKeyNavbarHideLabels);

    // Set once we actually rebuild bar.items below (add, remove, or pure reorder) -- read
    // further down to decide whether the pill's geometry needs a fresh settled layout pass, not
    // just when the platter's own frame size changed.
    BOOL itemsRebuilt = NO;
    if (![sources isEqualToArray:bar.sources]) {
        itemsRebuilt = YES;
        // Which source view the current selection and lastRealItem point at, not which index -- a
        // tab removed earlier in the list would shift every later index by one, and an index-based
        // remap would hand the pill to the wrong tab.
        NSUInteger oldSelIndex = [bar.items indexOfObject:bar.selectedItem];
        UIView *oldSelSource = (oldSelIndex != NSNotFound && oldSelIndex < bar.sources.count) ? bar.sources[oldSelIndex] : nil;
        NSUInteger oldLastIndex = [bar.items indexOfObject:bar.lastRealItem];
        UIView *oldLastSource = (oldLastIndex != NSNotFound && oldLastIndex < bar.sources.count) ? bar.sources[oldLastIndex] : nil;
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray array];
        for (UIView *source in sources) [items addObject:[[UITabBarItem alloc] initWithTitle:hideLabels ? nil : labelIn(source).text image:nil tag:items.count]];
        bar.sources = sources;
        [bar setItems:items animated:NO];
        // setItems: tears down and rebuilds every private per-item view, not just the ones that
        // actually changed -- so without forcing that rebuild to finish synchronously right here,
        // renderedCenterXForItem below (which the selection pill's position comes from) can still see
        // yesterday's layout, stale views included. Harmless on most passes since nothing reads
        // positions until later in this same call, but on a tab *removal* specifically it is what kept
        // the pill sitting over a slot that no longer has an icon in it.
        [bar layoutIfNeeded];
        // Re-thread the selection through the rebuild by the view it belonged to, found above.
        if (oldSelSource) {
            NSUInteger newSelIndex = [sources indexOfObject:oldSelSource];
            if (newSelIndex != NSNotFound) bar.selectedItem = items[newSelIndex];
        }
        if (oldLastSource) {
            NSUInteger newLastIndex = [sources indexOfObject:oldLastSource];
            if (newLastIndex != NSNotFound) bar.lastRealItem = items[newLastIndex];
        }
    }

    UITabBarItem *selected = nil;
    BOOL missing = NO;
    for (NSUInteger i = 0; i < sources.count; i++) {
        UITabBarItem *item = bar.items[i];
        learnGlyphs(sources[i], item);
        missing |= !item.image || !item.selectedImage;
        NSString *title = hideLabels ? nil : labelIn(sources[i]).text;
        if (hideLabels ? item.title != nil : title.length && ![title isEqualToString:item.title]) item.title = title;
        // UIKit still positions the icon as if a label sat under it even once the title is nil, so with
        // labels hidden it reads high in the now-shorter pill (kNavPlatterHeightIconOnly below) instead
        // of truly centred. Nudging it down by imageInsets makes up the difference; zero once labels
        // come back, so the icon returns to UIKit's own icon+label centring untouched.
        UIEdgeInsets wantInsets = hideLabels ? UIEdgeInsetsMake(kNavIconOnlyImageShift, 0, -kNavIconOnlyImageShift, 0) : UIEdgeInsetsZero;
        if (!UIEdgeInsetsEqualToEdgeInsets(item.imageInsets, wantInsets)) item.imageInsets = wantInsets;
        if (!selected && isActive(sources[i]) && !isCreateSource(sources[i])) selected = item;
    }
    if (apartSource) {
        learnGlyphs(apartSource, bar.apartItem);
        missing |= !bar.apartItem.image || !bar.apartItem.selectedImage;
    }
    // Everywhere except a genuine external navigation change (rescanSelection == YES, see
    // syncBarExternalChange), our own lastRealItem -- set the moment our tap/drag flow actually commits
    // to a tab -- is trusted over this isActive scan. A tab the mod added itself never turns any
    // source's label white the way Spotify's own tabs do, so without this, the previous *real* tab
    // (still reading isActive here, since Spotify's own stack never left it) kept winning this scan and
    // dragging the selection straight back to it on the very next layout pass.
    // While Create's menu is up the pill stays on Create; settleAfterCreate decides where it goes after.
    if ((rescanSelection && !bar.awaitingCreateClose) || !bar.lastRealItem) {
        if (selected && bar.selectedItem != selected) bar.selectedItem = selected;
        if (selected) bar.lastRealItem = selected;
    }
    // The apart tab's page being the open one, from Spotify's own labels, when a link or the drawer opened it. A
    // tab of the mod's own never paints one, and is known from its button's tap alone.
    if (rescanSelection && !bar.awaitingCreateClose && !selected && apartSource && !isCreateSource(apartSource) && isActive(apartSource)) bar.apartSelected = YES;
    // With the apart tab open the capsule has no tab selected (no pill).
    if (bar.apartSelected && !bar.awaitingCreateClose && bar.selectedItem) bar.selectedItem = nil;
    // Glyphs of the selected and the other items are painted by paintGlyphs, from the bar's own layout.
    paintGlyphs(bar);
    // An icon view Spotify has not built yet is looked for again shortly, not on the next touch.
    // Kept on stockBar itself, not one counter shared by every bar for the whole life of the
    // process -- that shared counter let a source that took a few tries early on spend the entire
    // budget, leaving a *different*, later source (a tab added afterwards, say) with no image and
    // no active/filled variant to swap to on selection, and nothing left to retry it with for the
    // rest of the session.
    NSNumber *retriesBox = objc_getAssociatedObject(stockBar, &kRetriesKey);
    NSUInteger retries = retriesBox.unsignedIntegerValue;
    if (missing) {
        if (retries < 40) {
            objc_setAssociatedObject(stockBar, &kRetriesKey, @(retries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                syncBar(stockBar);
            });
        }
    } else if (retriesBox) {
        // Every icon is in; the next source that comes up short gets its own fresh 40 tries
        // instead of whatever this run happened to leave over.
        objc_setAssociatedObject(stockBar, &kRetriesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGRect bounds = stockBar.bounds;
    CGFloat width = bounds.size.width;
    // height is the *room*, not the pill: UIKit's own tab bar can ask for as much as 83pt here
    // (harness/tabbar/README.md), most of which is the reserved home-indicator strip below the
    // platter, not glass. host stays that tall so the room-making math elsewhere is untouched; only
    // the visible pieces (bar, navGlass, navTint) are pinned to the fixed platter height below.
    CGFloat height = MAX(bounds.size.height, glassHeight(bar, stockBar));
    // Lifted off the very bottom edge by kNavGlassBottomMargin, so the pill floats the way real
    // Liquid Glass does on iOS 26+, instead of the legacy approximation's edge-to-edge slab.
    CGRect frame = CGRectMake(0, CGRectGetMaxY(bounds) - height - kNavGlassBottomMargin, width, height);
    if (!CGRectEqualToRect(host.frame, frame)) host.frame = frame;

    // The pill's own width, not the bar's: with itemWidth/itemPositioning centered above, sources.count
    // tabs take up exactly this much room, so the capsule hugs them and grows/shrinks with the tab
    // count instead of always spanning edge to edge like the old solid navbar did.
    // Past however many tabs kNavItemWidth's fixed 90pt would overflow the platter's own max width
    // for, each slot narrows just enough for all of them to still fit at that same width -- not the
    // width itself growing past what kNavGlassMargin leaves it. Below that count nothing changes.
    CGFloat platterHeight = MIN(hideLabels ? kNavPlatterHeightIconOnly : kNavPlatterHeight, height);
    // The apart tab's button stands beside the capsule, as high as it is, and the two are centered together.
    CGFloat apartRoom = apartSource ? platterHeight + SGRGrid : 0;
    CGFloat availableWidth = width - kNavGlassMargin * 2 - apartRoom;
    CGFloat naturalWidth = kNavItemWidth * sources.count + kNavItemSpacing * (sources.count - 1);
    CGFloat itemWidth = naturalWidth > availableWidth
        ? MAX(1, (availableWidth - kNavItemSpacing * (sources.count - 1)) / sources.count)
        : kNavItemWidth;
    if (bar.itemWidth != itemWidth) bar.itemWidth = itemWidth;
    CGFloat contentWidth = MIN(availableWidth, naturalWidth);
    // A small gap off host's top too, not just its bottom (kNavGlassBottomMargin): host's top edge sits
    // right where the now-playing card's bottom edge is, so a platter pinned at y=0 touched the card
    // directly with no breathing room between the two floating pieces.
    CGFloat platterY = MIN(kNavGlassBottomMargin, MAX(0, height - platterHeight));
    CGFloat groupX = floor((width - contentWidth - apartRoom) / 2);
    CGRect platterFrame = CGRectMake(groupX, platterY, contentWidth, platterHeight);
    CGRect apartFrame = apartSource ? CGRectMake(groupX + contentWidth + SGRGrid, platterY, platterHeight, platterHeight) : CGRectZero;
    BOOL frameChanged = !CGRectEqualToRect(bar.frame, platterFrame);
    if (frameChanged) bar.frame = platterFrame;
    // UIKit lays its private per-item buttons out lazily on the next runloop pass, not synchronously the
    // instant frame (or items) changes -- so reading their rendered positions (renderedCenterXForItem,
    // below) right after resizing the bar, e.g. when a tab was just added or removed, would still see
    // yesterday's layout. Forcing it here is what a tab-count change was missing: the pill used to land
    // exactly where the old item count put it, not where the new one actually renders.
    // A pure reorder (same count, so the platter itself is the same size) still moved every
    // button to a new slot in bar.items -- frameChanged alone missed that case, and
    // renderedCenterXForItem below kept reading whichever stale button positions were still
    // settled from before the reorder, which is what let the pill drift off to the side of the
    // icon it was supposed to sit under.
    if (frameChanged || itemsRebuilt) [bar layoutIfNeeded];

    // A glass capsule behind the bar, as NowPlayingBar.x backs the mini player; radius half its height.
    UIView *navGlass = SGGlassFor(host, &kNavGlassKey);
    navGlass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    CGRect glassFrame = platterFrame;
    if (!CGRectEqualToRect(navGlass.frame, glassFrame)) navGlass.frame = glassFrame;
    SGShapeGlass(navGlass, glassFrame.size.height / 2, NO);

    UIView *navTint = SGRGlassFilm(host, &kNavTintKey, navGlass, glassFrame.size.height / 2);

    // A dark capsule behind the selected icon only - the closest legacy stand-in for iOS 26+'s glass
    // "selection bubble". Sits above the tint so it reads as a shadow in the material, below the
    // (transparent) bar itself so the icon still draws on top of it.
    // Solid black (not Telegram's ~10% white lens glow): over navTint's 16% white film,
    // anything under ~50% alpha reads as washed-out grey instead of a clean black capsule.
    UIView *selPill = SGLazyChild(host, &kSelPillKey, ^UIView *{
        UIView *v = [UIView new];
        v.userInteractionEnabled = NO;
        v.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        v.layer.cornerCurve = kCACornerCurveContinuous;
        return v;
    });
    if (selPill.superview != host) [host insertSubview:selPill aboveSubview:navTint];
    // bar.selectedItem updates the instant UIKit processes a real tap (or our own drag handler sets
    // it), well before Spotify repaints the label isActive polls below -- keying the pill off that
    // polled state was the ~1s lag between tapping a tab and the pill actually moving there. syncBar is
    // now the pill's only writer -- dragged: no longer touches its frame directly -- so there is exactly
    // one animation per selection change, never two fighting over the same frame.
    NSUInteger selIndex = [bar.items indexOfObject:bar.selectedItem];
    if (selIndex != NSNotFound && selIndex < sources.count) {
        CGFloat pillWidth = itemWidth - kSelPillInset * 2;
        CGFloat centerX = [bar renderedCenterXForItem:bar.selectedItem];
        CGFloat slotX = isnan(centerX)
            ? bar.frame.origin.x + selIndex * (itemWidth + kNavItemSpacing) + kSelPillInset
            : bar.frame.origin.x + centerX - pillWidth / 2;
        CGRect pillFrame = CGRectMake(slotX, bar.frame.origin.y + kSelPillInset, pillWidth, bar.frame.size.height - kSelPillInset * 2);
        selPill.layer.cornerRadius = pillFrame.size.height / 2;
        BOOL wasVisible = !selPill.hidden;
        selPill.hidden = NO;
        if (!CGRectEqualToRect(selPill.frame, pillFrame)) {
            if (wasVisible && !CGRectIsEmpty(selPill.frame)) {
                // Slides to the new slot instead of jumping -- the pill's one and only animation now,
                // on a tap or a drag alike, with no raw finger-tracking step before it.
                [UIView animateWithDuration:0.25 delay:0
                    options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                    animations:^{ selPill.frame = pillFrame; } completion:nil];
            } else {
                selPill.frame = pillFrame;
            }
        }
    } else {
        selPill.hidden = YES;
    }
    placeCompact(stockBar, bar, host, sources, platterFrame, apartFrame, navGlass, navTint, selPill);

    if (host.superview != stockBar) [stockBar addSubview:host];
    else if (stockBar.subviews.lastObject != host) [stockBar bringSubviewToFront:host];
    makeRoom(containerOf(stockBar));
}

#pragma mark - hooks

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive.
static void itemDidLayOut(UIView *item) {
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    SGRComposeTabBar(bar);
    holdHome(bar);
    syncBar(bar);
}

%group LegacyTabBar

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    %orig;
    SGRComposeTabBar((UIView *)self);
    for (UIView *sub in ((UIView *)self).subviews) {
        if (![sub isKindOfClass:SGRLegacyTabBarHost.class]) [sub layoutIfNeeded];
    }
    holdHome((UIView *)self);
    syncBar((UIView *)self);
}
%end

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

// A tab changed from elsewhere (a link, the side drawer) repaints the labels without a layout pass.
%hook _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (void)setSelectedViewController:(UIViewController *)controller {
    %orig;
    // Spotify repaints its labels a moment after the controller changes, so the first look can still
    // find the old tab painted white; the second, once it has.
    dispatch_async(dispatch_get_main_queue(), ^{
        // Another tab brings the minimized bar back (HIG, Tab bars). Create's menu stands under the compact bar
        // and hides nothing of it, so the bar stays while the menu is up (settleAfterCreate looks again after).
        UIView *bar = sg_stockBar;
        SGRLegacyTabBar *legacy = bar ? objc_getAssociatedObject(bar, &kBarKey) : nil;
        if (!(sg_minimized && legacy.awaitingCreateClose)) SGRLegacySetTabBarMinimized(NO, YES);
        if (bar) syncBarExternalChange(bar);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *bar = sg_stockBar;
        if (bar) syncBarExternalChange(bar);
    });
}
// The message bar coming or going changes the view's safe area before Spotify lays the bar out for it,
// so the room follows in that same pass, and inside the message bar's animation.
- (void)viewSafeAreaInsetsDidChange {
    %orig;
    makeRoom((UIViewController *)self);
}
%end

%end

BOOL SGRLegacyTabBarOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Below 26 the system draws no glass of its own, so the redesign's bar is this one whatever it is made
        // of; SGGlassFor makes the pane, a plain blur or legacy glass by the switch.
        if (@available(iOS 26.0, *)) return;
        on = SGRedesignedUI();
    });
    return on;
}

%ctor {
    if (!SGRLegacyTabBarOn()) return;
    %init(LegacyTabBar);
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
        @"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl",
    ]);
}
