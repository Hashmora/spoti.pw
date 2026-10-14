// The bar of a page under SPNavigationBar (trees/continuous/7.txt, 8.txt). Spotify draws it as UIKit's bar with no
// background of its own over a blur of its own, a plain view in the navigation controller's view that holds a
// UIVisualEffectView and is painted #000000 (7.txt:936); the back button is a _UIButtonBarButton at the leading
// edge of the bar's content view, the title a _UINavigationBarTitleControl with a UILabel, and a page's ⋯ the
// Encore button in a _UIButtonBarStackView at the trailing edge (8.txt:204).
//
// The playlist, album and artist pages have none of that: the page's field to the top of the screen, a glass
// circle for Back and for ⋯ at the corners, level with each other, and the name on a glass capsule between them.
// So here the blur is drawn by nothing, the bar takes no touches, Back and ⋯ are pinned to the page the way the
// other pages pin theirs (SGRPinnedMore, SGRPinnedBackOf), and the title control carries the capsule, as
// Playlist/PlaylistBar.x gives the playlist's name its own.
//
// The bar and its blur are the navigation controller's, shared by every page on its stack, so each is given back
// as the page goes (SGRUndressBarPage). What is concealed is Spotify's own controls, not replaced: the pinned ⋯
// fires the page's own ⋯ -- the Encore button in this page's bar -- and Back pops the navigation controller.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kMoreKey, kProxyKey, kTitleGlassKey, kTitleWatchedKey;

// Side padding of the title inside its capsule, and the room the two corner buttons leave it: the same as the
// playlist's name has (Playlist/PlaylistBar.x).
static const CGFloat kTitlePadding = 18, kTitleHeight = 44, kCorner = 16, kGap = 8;

Class SGRPageClass(NSString *module, NSString *name) {
    NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@", (unsigned long)module.length, module, (unsigned long)name.length, name];
    return NSClassFromString(mangled) ?: NSClassFromString([NSString stringWithFormat:@"%@.%@", module, name]);
}

#pragma mark - the controls of the bar

static UIView *subviewNamed(UIView *host, NSString *name) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:name]) return sub;
    }
    return nil;
}

// The bar's content view, 44pt high under the status bar, and what UIKit puts in it.
static UIView *contentOf(UINavigationBar *bar) {
    for (UIView *sub in bar.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"_UINavigationBarContentView"]) return sub;
    }
    return nil;
}

// The page's own ⋯: the first control of the bar's trailing stack, which holds nothing on a page without one.
// Looked for in this bar and nowhere else, so what the ⋯ fires can never be a ⋯ of the player's.
static UIView *moreOf(UIView *content) {
    UIView *stack = subviewNamed(content, @"_UIButtonBarStackView");
    UIView *button = stack.subviews.firstObject;
    return button.bounds.size.width > 1 ? button : nil;
}

static void conceal(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static void reveal(UIView *view) {
    if (!view) return;
    view.layer.hidden = NO;
    view.layer.mask = nil;
    view.userInteractionEnabled = YES;
    view.accessibilityElementsHidden = NO;
}

// Spotify's blur: the plain view of the navigation controller's that holds a visual effect view.
static UIView *blurOf(UINavigationController *navigation) {
    for (UIView *sub in navigation.view.subviews) {
        if (![sub isMemberOfClass:UIView.class]) continue;
        for (UIView *inner in sub.subviews) {
            if ([inner isKindOfClass:UIVisualEffectView.class]) return sub;
        }
    }
    return nil;
}

#pragma mark - Back

// What the pinned Back reads and fires: a control of the redesign's own that stands in for the bar's back button
// and pops the stack, which is all that button does.
@interface SGRBackProxy : UIControl
@property (nonatomic, weak) UINavigationController *navigation;
@end

@implementation SGRBackProxy
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self addTarget:self action:@selector(sgr_back) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)sgr_back {
    [self.navigation popViewControllerAnimated:YES];
}

- (BOOL)accessibilityActivate {
    [self sgr_back];
    return YES;
}
@end

#pragma mark - the title

static void glassTitle(UIView *title) {
    UILabel *label = nil;
    for (UIView *sub in title.subviews) {
        for (UIView *inner in sub.subviews) {
            if (!label && [inner isKindOfClass:UILabel.class]) label = (UILabel *)inner;
        }
    }
    if (!label.text.length) return;
    CGFloat screen = title.window ? title.window.bounds.size.width : 390;
    CGFloat room = screen - 2 * (kCorner + SGRGlassCircleSize + kGap);
    CGFloat wanted = ceil([label sizeThatFits:CGSizeMake(CGFLOAT_MAX, kTitleHeight)].width) + 2 * kTitlePadding;
    CGFloat width = MIN(MAX(wanted, kTitleHeight), room);
    // The control is as small as its label, and the capsule is a subview that reaches past it.
    for (UIView *v = title; v && ![v isKindOfClass:UINavigationBar.class]; v = v.superview) {
        if (v.clipsToBounds) v.clipsToBounds = NO;
    }
    SGRGlassCapsuleInside(title, &kTitleGlassKey, CGSizeMake(width, kTitleHeight), NO);
}

// The title is laid out again as its text arrives, which reaches neither the page nor the bar's content view the
// page's pass works from: it is watched for its own layout.
static void watchTitle(UIView *title) {
    if (objc_getAssociatedObject(title, &kTitleWatchedKey)) return;
    if (SGRObserveLayout(title, ^(UIView *view) { glassTitle(view); })) {
        objc_setAssociatedObject(title, &kTitleWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - the page

static BOOL isOnScreen(UIViewController *page, UINavigationController *navigation) {
    for (UIViewController *vc = page; vc; vc = vc.parentViewController) {
        if (vc == navigation.topViewController) return YES;
    }
    return NO;
}

void SGRDressBarPage(UIViewController *page) {
    UIView *view = page.viewIfLoaded;
    UINavigationController *navigation = page.navigationController;
    if (!view.window || !navigation || !isOnScreen(page, navigation)) return;
    UINavigationBar *bar = navigation.navigationBar;
    UIView *content = contentOf(bar);
    if (!content) return;

    UIView *blur = blurOf(navigation);
    if (blur) {
        if (!blur.layer.mask) blur.layer.mask = [CALayer layer];
        if (blur.userInteractionEnabled) blur.userInteractionEnabled = NO;
    }
    // The bar is above the page and would take the touches meant for the buttons pinned to it.
    if (bar.userInteractionEnabled) bar.userInteractionEnabled = NO;

    UIView *back = subviewNamed(content, @"_UIButtonBarButton");
    conceal(back);
    SGRBackProxy *proxy = objc_getAssociatedObject(view, &kProxyKey);
    if (!proxy) {
        proxy = [[SGRBackProxy alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(view, &kProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    proxy.navigation = navigation;
    SGRPinnedBackOf(view, proxy);

    UIView *more = moreOf(content);
    conceal(more);
    SGRPinnedMore(view, &kMoreKey, more);

    UIView *title = subviewNamed(content, @"_UINavigationBarTitleControl");
    if (title) {
        glassTitle(title);
        watchTitle(title);
    }
}

void SGRUndressBarPage(UIViewController *page) {
    UINavigationController *navigation = page.navigationController;
    if (!navigation) return;
    UINavigationBar *bar = navigation.navigationBar;
    UIView *content = contentOf(bar);
    reveal(subviewNamed(content, @"_UIButtonBarButton"));
    reveal(moreOf(content));
    bar.userInteractionEnabled = YES;
    UIView *blur = blurOf(navigation);
    blur.layer.mask = nil;
    blur.userInteractionEnabled = YES;
    // The capsule is the title control's, which the next page's title may be too: it goes, and the next pass of
    // the page that wants one makes it again.
    UIView *title = subviewNamed(content, @"_UINavigationBarTitleControl");
    [(UIView *)objc_getAssociatedObject(title, &kTitleGlassKey) removeFromSuperview];
}
