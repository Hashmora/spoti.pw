// Tab bar: Spotify's own bar stays where it is but goes invisible, and a system UITabBar sits on top
// of it. On iOS 26+ with UIDesignRequiresCompatibility off, UIKit draws that bar as real Liquid Glass
// (selection bubble, lensing, light/dark adaptation) with no glass API of ours. Spotify's bar keeps
// its frame, so the page insets and the now playing bar stay where Spotify puts them; where the system
// bar is taller than Spotify's, Spotify is made to leave it the room (see "room for the glass bar").
//
// A tab picked on the system bar is passed on as a tap on the hidden Spotify item it mirrors, and the
// system bar's selection follows whichever Spotify label is painted white. Navbar.x composes the
// hidden row, so its order, hidden tabs and tabs of the mod's own carry over. Always on in the redesign.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView of
//   ElementContentView<TabBarItemElement>, each with an SPTEncoreIconView and an SPTEncoreLabel.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Settings/SGPage.h"
#import "Headers/SPTEncoreIconView.h"
#import <objc/message.h>

static char kBarKey, kHostKey, kNavGlassKey, kNavTintKey, kSelPillKey, kRetriesKey;
static const CGFloat kNavGlassMargin = 16;       // side gap, so the bar floats instead of touching the edges
static const CGFloat kNavGlassBottomMargin = 8;  // gap under the bar, so it floats above the edge like iOS 26+
// The pill itself, never the safe-area room under it: glassHeight() below can be as tall as 83pt on
// a Face ID phone (harness/tabbar/README.md) because that includes the reserved home-indicator strip,
// which is not glass. 64pt matches Telegram's own tab bar pill exactly (TabBarComponent.swift: a
// 56pt item row plus 4pt of inner inset top and bottom). Radius is always half of this -- a true
// capsule -- never a fixed corner radius that stops matching once the height changes.
static const CGFloat kNavPlatterHeight = 64;
// Icons-only is a squarer pill, not the same 64pt built to hold a label underneath too -- tall and
// mostly empty otherwise, with the icon floating off-centre in it (UIKit still lays the icon out as
// if a label sat below it, even once the title itself is nil). kNavIconOnlyImageShift below is a
// starting guess at how far that leaves the icon short of true centre in the shorter pill -- tune
// both together against a real device, this wasn't checked on screen.
static const CGFloat kNavPlatterHeightIconOnly = 52;
static const CGFloat kNavIconOnlyImageShift = 6;
static const CGFloat kNavItemSpacing = 4;    // tighter gaps between icons, like the real iOS 26+ pill
static const CGFloat kSelPillInset = 3;      // small gap between the selection pill and the platter's own
                                              // top/bottom edge, so it reads as a shape floating inside the
                                              // bar rather than a slab reaching its full height
static const CGFloat kNavItemWidth = 90;     // fixed per-tab width so the pill hugs its items and self-sizes
                                              // instead of stretching them across whatever width it's given --
                                              // wider than before, closer to the room a label like "Your
                                              // Library" actually needs, per the reference screenshot
static __weak UIView *sg_stockBar;
static CGFloat sg_room, sg_glassHeight;   // see "room for the glass bar"

// Components/TabSelectionRecognizer/Sources/TabSelectionRecognizer.swift, ported as-is: state goes to
// Began the instant a finger touches down (no distance or duration threshold the way a pan or a long
// press has), and Changed on every move after that, so a caller can follow the finger from frame one.
@interface SGTabDragRecognizer : UIGestureRecognizer
@property (nonatomic) CGPoint currentLocation;
@property (nonatomic) BOOL moved;
@end

@implementation SGTabDragRecognizer

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

@interface SGRSystemTabBar : UITabBar <UITabBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *stockBar;
@property (nonatomic, copy) NSArray<UIView *> *sources;
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
@end

static void syncBar(UIView *stockBar);
// Called only when Spotify's own navigation genuinely changed the selected controller from outside our
// bar (a link, the side drawer) -- see the TabBarContainerImpl hook below. Every other caller goes
// through plain syncBar, which trusts whatever tab our own tap/drag handling last confirmed
// (SGRSystemTabBar.lastRealItem) over Spotify's isActive/label-color heuristic. That heuristic never
// clears for a tab the mod added itself: Spotify's own navigation stack never touched it, so the
// previously active *real* tab's label just stays white forever, and re-scanning it on every layout
// pass kept snapping the selection (and the pill) back to that old tab.
static void syncBarExternalChange(UIView *stockBar);
static void syncBarCore(UIView *stockBar, BOOL rescanSelection);

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

// Navbar.x never reorders Spotify's row and appends the mod's own tabs after it, so Home stays first.
static BOOL isHome(UIView *item, UIView *tabBar) {
    return item && item == SGRowIn(tabBar).arrangedSubviews.firstObject;
}

// Create never pushes a screen -- tapping it only pops CreateMenu's own option list open over whatever
// is already on screen, and tapping anywhere dismisses that list again with nothing having navigated.
// So it must never become the bar's real "selected" tab: the pill parking on it, or drifting toward
// its slot, would be showing a screen that was never actually opened.
static BOOL isCreateSource(UIView *source) {
    static Class createClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ createClass = NSClassFromString(@"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView"); });
    return createClass && [source isKindOfClass:createClass];
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

// The SPTEncoreIcon an icon view was built with. Encore keeps it in a Swift ivar with no getter.
static id encoreIconOf(UIView *view) {
    Ivar ivar = class_getInstanceVariable(view.class, "icon");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(view, ivar) : nil;
}

// Encore draws a tab's icon from one SPTEncoreIcon in two states: isActive picks its filled variant.
// Both are drawn on an icon view of our own, off screen, so the images do not wait for Spotify's
// views to lay out and paint, and UITabBar swaps image and selectedImage itself.
static UIImage *glyphOf(UIView *item, BOOL active) {
    UIView *live = iconIn(item);
    if (!live) return nil;
    CGSize size = live.bounds.size;
    id icon = encoreIconOf(live);
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    if (icon && viewClass) {
        static NSCache<NSString *, UIImage *> *cache;
        if (!cache) cache = [NSCache new];
        NSString *key = [NSString stringWithFormat:@"%@ %d %@", [icon respondsToSelector:@selector(name)] ? [icon name] : icon, active, NSStringFromCGSize(size)];
        UIImage *cached = [cache objectForKey:key];
        if (cached) return cached;
        SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
        view.frame = (CGRect){CGPointZero, size};
        [view setForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
        [view layoutIfNeeded];
        UIImage *image = renderLayer(view.layer, size);
        if (image) {
            [cache setObject:image forKey:key];
            return image;
        }
    }
    // Tabs of the mod's own draw a UIImageView, or an icon Encore would not draw off screen.
    return size.width >= 2 ? renderLayer(live.layer, size) : nil;
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
            SGLog(@"tab bar: tap -> %@ %@", NSStringFromClass([target class]), NSStringFromSelector(action));
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
        SGLog(@"tab bar: tap -> control %@", NSStringFromClass(v.class));
        [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        sent = YES;
    });
    if (!sent) {
        NSMutableString *out = [NSMutableString stringWithFormat:@"tab bar: nothing to tap in %@", NSStringFromClass(item.class)];
        SGForEachView(item, ^(UIView *v) {
            for (UIGestureRecognizer *r in v.gestureRecognizers) [out appendFormat:@"\n  %@ on %@", r, NSStringFromClass(v.class)];
        });
        SGLogLong(@"navbar", out);
    }
}

// A tap (or a there-and-back drag) that ends back on the tab that was already open never moves the
// pill -- selectedItem never changed, there's nothing for it to move to -- but it should still feel
// like the tap registered. A small scale pulse on the icon itself stands in for that.
static void bumpIcon(UITabBar *bar, UITabBarItem *item) {
    if (!item) return;
    __block UIView *iconView = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (iconView || ![v isKindOfClass:UIImageView.class]) return;
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

#pragma mark - the system bar

@implementation SGRSystemTabBar

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    NSUInteger index = [self.items indexOfObject:item];
    if (index == NSNotFound || index >= self.sources.count) return;
    UIView *source = self.sources[index];
    if (isCreateSource(source)) {
        // Just pops the menu open -- never a real navigation -- so the bar's selection (and the pill
        // with it) snaps straight back to whatever tab was actually open a moment ago, instead of
        // resting on Create or on wherever Create's own slot happens to sit.
        forwardTap(source);
        if (self.lastRealItem) self.selectedItem = self.lastRealItem;
        // Create never gets a real screen, so nothing subsequently navigates and nothing else would
        // prompt a resync once its popover closes -- unlike a real tab below, where Spotify's own
        // navigation event does that later on its own. Force it here too, on the same delay, so the
        // pill is guaranteed to still be sitting over lastRealItem once the popover is gone.
        UIView *stockBar = self.stockBar;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (stockBar) syncBar(stockBar);
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
- (void)dragged:(SGTabDragRecognizer *)g {
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
@interface SGRTabBarHost : UIView
@end

@implementation SGRTabBarHost
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = [super safeAreaInsets];
    // The host's own frame now stands kNavGlassBottomMargin above the screen's real safe area, which
    // hands it that much *extra* raw inset on its own. Left alone, UITabBar would read that as more
    // home-indicator padding to reserve and push the icon/label stack up, off-centre in the pill.
    // Canceling it out here keeps the bar's internal vertical centering exactly as it was undocked.
    insets.bottom = MAX(0, insets.bottom - sg_room - kNavGlassBottomMargin);
    return insets;
}
@end

@interface SGRHomeHold : UILongPressGestureRecognizer
@end

@implementation SGRHomeHold
+ (void)held:(SGRHomeHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) SGOpenModSettings(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so Home is not tapped too.
static void holdHome(UIView *stockBar) {
    UIView *home = SGRowIn(stockBar).arrangedSubviews.firstObject;
    if (!home) return;
    for (UIGestureRecognizer *recognizer in home.gestureRecognizers) {
        if ([recognizer isKindOfClass:SGRHomeHold.class]) return;
    }
    [home addGestureRecognizer:[[SGRHomeHold alloc] initWithTarget:SGRHomeHold.class action:@selector(held:)]];
}

static void logBarOnce(UITabBar *bar) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGLogLong(@"navbar", [NSString stringWithFormat:@"system tab bar %@\n%@", NSStringFromCGRect(bar.superview.frame), [bar recursiveDescription]]);
        });
    });
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
// phone, by the safe area of the view the bar stands in. SGRTabBarHost keeps the room out of that; if
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
    SGLog(@"tab bar: %.0f pt of room made under Spotify's bar for the glass bar's %.0f, over an inset of %.0f", room, height, inset);
}

static void syncBar(UIView *stockBar) {
    syncBarCore(stockBar, NO);
}

static void syncBarExternalChange(UIView *stockBar) {
    syncBarCore(stockBar, YES);
}

static void syncBarCore(UIView *stockBar, BOOL rescanSelection) {
    sg_stockBar = stockBar;

    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar) {
        bar = [[SGRSystemTabBar alloc] initWithFrame:stockBar.bounds];
        // UIKit draws the glass in the appearance the bar inherits, and the bar is outside the navigation
        // stacks Spotify makes dark itself (-[SPNavigationController viewDidLoad] while +[SPTLiquidGlass
        // isEnabled]), so a phone in light mode had it light over Spotify's black. Spotify is dark whatever
        // the system is, and so is the bar.
        bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        // Below iOS 26 UITabBar paints its own translucent chrome, which sits in front of navGlass
        // (below) and hides it completely. iOS 26+ is left alone: UIKit already draws real Liquid
        // Glass there on its own, and a transparent appearance would fight that.
        // Always transparent: navGlass below is the only real glass pane now, shaped and sized as
        // one true capsule. Leaving UIKit's iOS 26+ auto-glass on here stacked a second, edge-to-edge
        // material behind ours at a different height, which is what looked off next to a proper pill.
        bar.translucent = YES;
        bar.backgroundImage = [UIImage new];
        bar.shadowImage = [UIImage new];
        bar.backgroundColor = UIColor.clearColor;
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithTransparentBackground];
        bar.standardAppearance = appearance;
        if (@available(iOS 15.0, *)) bar.scrollEdgeAppearance = appearance;
        bar.delegate = bar;
        bar.stockBar = stockBar;
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:bar action:@selector(held:)];
        hold.delegate = bar;
        [bar addGestureRecognizer:hold];
        bar.hold = hold;
        // Telegram's own drag-to-switch, not an approximation of it anymore: SGTabDragRecognizer above
        // is TabSelectionRecognizer.swift ported directly.
        SGTabDragRecognizer *drag = [[SGTabDragRecognizer alloc] initWithTarget:bar action:@selector(dragged:)];
        drag.delegate = bar;
        [bar addGestureRecognizer:drag];
        bar.drag = drag;
        objc_setAssociatedObject(stockBar, &kBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRTabBarHost *host = [SGRTabBarHost new];
        [host addSubview:bar];
        objc_setAssociatedObject(stockBar, &kHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    bar.tintColor = SGRAccent();
    // UIKit's own default unselected tint (a mid grey in dark mode) is what made the three inactive
    // icons read as grey instead of white, next to the reference screenshot's fully white inactive
    // icons. glyphOf renders every icon as an always-template image, so tint color is the only thing
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

    NSArray<UIView *> *sources = tabItems(stockBar);
    if (!sources.count) return;
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
        NSMutableString *out = [NSMutableString stringWithString:@"tab bar icons"];
        for (UIView *source in sources) {
            UIView *live = iconIn(source);
            id icon = live ? encoreIconOf(live) : nil;
            id variant = [icon respondsToSelector:NSSelectorFromString(@"active")] ? ((id (*)(id, SEL))objc_msgSend)(icon, NSSelectorFromString(@"active")) : nil;
            [out appendFormat:@"\n  %@: %@ icon %@ active-variant %@ live-isActive %d label-white %d", labelIn(source).text, NSStringFromClass(live.class),
                 [icon respondsToSelector:@selector(name)] ? [icon name] : icon, [variant respondsToSelector:@selector(name)] ? [variant name] : variant,
                 [live respondsToSelector:@selector(isActive)] ? [(SPTEncoreIconView *)live isActive] : -1, isActive(source)];
        }
        SGLogLong(@"navbar", out);
    }

    UITabBarItem *selected = nil;
    BOOL missing = NO;
    for (NSUInteger i = 0; i < sources.count; i++) {
        UITabBarItem *item = bar.items[i];
        if (!item.image) item.image = glyphOf(sources[i], NO);
        if (!item.selectedImage || item.selectedImage == item.image) item.selectedImage = glyphOf(sources[i], YES);
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
    // Everywhere except a genuine external navigation change (rescanSelection == YES, see
    // syncBarExternalChange), our own lastRealItem -- set the moment our tap/drag flow actually commits
    // to a tab -- is trusted over this isActive scan. A tab the mod added itself never turns any
    // source's label white the way Spotify's own tabs do, so without this, the previous *real* tab
    // (still reading isActive here, since Spotify's own stack never left it) kept winning this scan and
    // dragging the selection straight back to it on the very next layout pass.
    if (rescanSelection || !bar.lastRealItem) {
        if (selected && bar.selectedItem != selected) bar.selectedItem = selected;
        if (selected) bar.lastRealItem = selected;
    }
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
    CGFloat availableWidth = width - kNavGlassMargin * 2;
    CGFloat naturalWidth = kNavItemWidth * sources.count + kNavItemSpacing * (sources.count - 1);
    CGFloat itemWidth = naturalWidth > availableWidth
        ? MAX(1, (availableWidth - kNavItemSpacing * (sources.count - 1)) / sources.count)
        : kNavItemWidth;
    if (bar.itemWidth != itemWidth) bar.itemWidth = itemWidth;
    CGFloat contentWidth = MIN(availableWidth, naturalWidth);
    CGFloat platterHeight = MIN(hideLabels ? kNavPlatterHeightIconOnly : kNavPlatterHeight, height);
    // A small gap off host's top too, not just its bottom (kNavGlassBottomMargin): host's top edge sits
    // right where the now-playing card's bottom edge is, so a platter pinned at y=0 touched the card
    // directly with no breathing room between the two floating pieces.
    CGFloat platterY = MIN(kNavGlassBottomMargin, MAX(0, height - platterHeight));
    CGRect platterFrame = CGRectMake(floor((width - contentWidth) / 2), platterY, contentWidth, platterHeight);
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

    // A glass pane behind the bar, the same way NowPlayingBar.x backs the mini player: real
    // UIGlassEffect on iOS 26+ (on top of what UITabBar already draws itself), the legacy
    // approximation below it when that switch is on (Core/SGGlass.m). Same capsule as the bar
    // itself, radius always exactly half its height -- like Telegram's own
    // backgroundSize.height * 0.5 -- so it reads as a pill, not a rounded slab.
    UIView *navGlass = SGGlassFor(host, &kNavGlassKey);
    navGlass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    CGRect glassFrame = platterFrame;
    if (!CGRectEqualToRect(navGlass.frame, glassFrame)) navGlass.frame = glassFrame;
    SGShapeGlass(navGlass, glassFrame.size.height / 2, NO);

    // A faint white film over the glass, the same trick SGRGlass.m uses for prominent capsules:
    // real Liquid Glass gets a touch of it too, and it's what keeps the bar from vanishing into
    // Spotify's near-black chrome below iOS 26.
    UIView *navTint = objc_getAssociatedObject(host, &kNavTintKey);
    if (!navTint) {
        navTint = [UIView new];
        navTint.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        navTint.userInteractionEnabled = NO;
        navTint.layer.cornerCurve = kCACornerCurveContinuous;
        navTint.layer.masksToBounds = YES;
        objc_setAssociatedObject(host, &kNavTintKey, navTint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (navTint.superview != host) [host insertSubview:navTint aboveSubview:navGlass];
    if (!CGRectEqualToRect(navTint.frame, glassFrame)) navTint.frame = glassFrame;
    navTint.layer.cornerRadius = glassFrame.size.height / 2;

    // A dark capsule behind the selected icon only - the closest legacy stand-in for iOS 26+'s glass
    // "selection bubble". Sits above the tint so it reads as a shadow in the material, below the
    // (transparent) bar itself so the icon still draws on top of it.
    UIView *selPill = objc_getAssociatedObject(host, &kSelPillKey);
    if (!selPill) {
        selPill = [UIView new];
        selPill.userInteractionEnabled = NO;
        // A real black, not the faint white glow Telegram's own *legacy* fallback formula gives
        // (LiquidLensView.swift's alpha:0.1 white -- tuned for a lens sitting over already-bright chat
        // content, not this). selPill sits over navTint's white 16% film, so anything much under ~50%
        // alpha read as washed-out grey rather than black once composited -- not what the reference
        // screenshot's clean, solid black capsule looks like.
        selPill.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        selPill.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(host, &kSelPillKey, selPill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
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

    if (host.superview != stockBar) [stockBar addSubview:host];
    else if (stockBar.subviews.lastObject != host) [stockBar bringSubviewToFront:host];
    logBarOnce(bar);
    makeRoom(containerOf(stockBar));
}

#pragma mark - hooks

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    %orig;
    SGRComposeTabBar((UIView *)self);
    for (UIView *sub in ((UIView *)self).subviews) {
        if (![sub isKindOfClass:SGRTabBarHost.class]) [sub layoutIfNeeded];
    }
    holdHome((UIView *)self);
    syncBar((UIView *)self);
    SGRLogTabBarRow((UIView *)self);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive.
static void itemDidLayOut(UIView *item) {
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    SGRComposeTabBar(bar);
    holdHome(bar);
    syncBar(bar);
    SGRLogTabBarRow(bar);
}

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
    dispatch_async(dispatch_get_main_queue(), ^{
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

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
        @"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl",
    ]);
}
