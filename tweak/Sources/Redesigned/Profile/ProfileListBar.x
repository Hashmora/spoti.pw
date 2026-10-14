// Profile lists, iOS < 26: Followers, Following and the playlists of a person. The page is a table under
// SPNavigationBar, UIKit's bar, which Spotify backs with a dark blur of its own. Here the blur goes, the back
// button stands on a glass circle and the title on a glass capsule, the same material as the round buttons of the
// playlist, album and artist pages (Playlist/PlaylistBar.x).
//
// Tree (trees/continuous/15.txt:415-436, 16.txt): in the navigation controller's UILayoutContainerView, over the
// page, a plain UIView 390x91 clips (bg none) holding a UIVisualEffectView whose _UIVisualEffectSubview is
// #1C1C1C@0.73, then SPNavigationBar {0, 47} 390x44. Its _UIBarBackground is already empty (a=0). In
// _UINavigationBarContentView: the back button, _UIButtonBarButton {0, 0} 48x44 holding a hidden
// _UIBackButtonMaskView and a _UIModernBarButton with the chevron, and _UINavigationBarTitleControl 72x22 with
// the page's name in a UILabel.
//
// The bar and its blur belong to the navigation controller, so every page of it shares them: they are dressed
// only while a profile list is the page on top, and put back as it leaves. Whether one is on top is read off the
// navigation controller at every pass (topViewController), not kept from appear/disappear callbacks: a swipe back
// that is let go fires them in an order that left the glass off and the blur back (device, 2026-10-15, 14.txt,
// 16.txt). UIKit builds the bar's buttons and its title control again whenever the item changes, after the bar's
// own pass, so the dressing is redone from the bar's, its content view's and the title's passes.
// The blur is taken out with an empty mask, not hidden: Spotify writes the layer's hidden itself and that brought
// the dark band back under the title (it flickered).
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Profile.h"

// The glass is as tall as the round buttons beside it on the playlist's pages; the name has this much on each side.
static const CGFloat kGlassHeight = 44, kTitlePadding = 18;

static char kBackGlassKey, kTitleGlassKey, kBackdropMaskKey, kTitleWatchedKey;

// What was dressed for a profile list, to be put back when none is on top.
static __weak UIView *sg_backHost;
static __weak UIView *sg_titleHost;
static __weak UIView *sg_backdrop;
static CALayer *sg_emptyMask;

static UIView *subviewNamed(UIView *host, NSString *name) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:name]) return sub;
    }
    return nil;
}

static UILabel *labelIn(UIView *host) {
    __block UILabel *found = nil;
    SGForEachView(host, ^(UIView *v) {
        if (!found && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) found = (UILabel *)v;
    });
    return found;
}

// The navigation controller's blur behind the bar: a plain UIView, the bar's sibling, whose first subview is a
// UIVisualEffectView, as tall as the bar's bottom edge (or collapsed to nothing while a page has no bar).
static UIView *backdropOf(UIView *bar) {
    for (UIView *sub in bar.superview.subviews) {
        if (sub == bar || ![sub isMemberOfClass:UIView.class]) continue;
        if (![sub.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) continue;
        if (sub.frame.size.height > CGRectGetMaxY(bar.frame) + 1) continue;
        return sub;
    }
    return nil;
}

static UINavigationController *navigationOf(UIView *bar) {
    for (UIResponder *r = bar; r; r = r.nextResponder) {
        if ([r isKindOfClass:UINavigationController.class]) return (UINavigationController *)r;
    }
    return nil;
}

static BOOL profileListOnTop(UIView *bar) {
    static Class list;
    if (!list) list = NSClassFromString(@"_TtC18Profile_CommonImpl25ProfileListViewController");
    UIViewController *top = navigationOf(bar).topViewController;
    return list && top && [top isKindOfClass:list] && top.viewIfLoaded.window;
}

static void update(UIView *bar);

static void dress(UIView *bar) {
    __block UIView *back = nil, *title = nil;
    SGForEachView(bar, ^(UIView *v) {
        NSString *name = NSStringFromClass(v.class);
        if (!back && [name isEqualToString:@"_UIButtonBarButton"] && subviewNamed(v, @"_UIBackButtonMaskView")) back = v;
        if (!title && [name isEqualToString:@"_UINavigationBarTitleControl"]) title = v;
    });

    // The glass goes in the control that draws the chevron, so the circle is centred on the glyph (the bar button
    // around it is 48pt wide and the glyph sits off its middle).
    UIView *backHost = back ? (subviewNamed(back, @"_UIModernBarButton") ?: back) : nil;
    if (backHost && backHost.bounds.size.width > 1) {
        UIView *glass = SGRGlassInside(backHost, &kBackGlassKey, kGlassHeight);
        if (glass) SGRShowGlass(glass, YES);
        sg_backHost = backHost;
    }

    UILabel *label = title ? labelIn(title) : nil;
    if (title && label && title.bounds.size.width > 1) {
        CGFloat text = ceil([label.text sizeWithAttributes:@{NSFontAttributeName: label.font}].width);
        CGFloat room = bar.bounds.size.width - 2 * (48 + SGRGrid);
        CGFloat width = MIN(MAX(text + 2 * kTitlePadding, kGlassHeight), room);
        // The control is as small as its label and the capsule reaches past it.
        for (UIView *v = title; v && ![v isKindOfClass:UINavigationBar.class]; v = v.superview) {
            if (v.clipsToBounds) v.clipsToBounds = NO;
        }
        UIView *glass = SGRGlassCapsuleInside(title, &kTitleGlassKey, CGSizeMake(width, kGlassHeight), NO);
        if (glass) SGRShowGlass(glass, YES);
        sg_titleHost = title;
        // The title control is laid out again as its text arrives, after the bar's own pass.
        if (!objc_getAssociatedObject(title, &kTitleWatchedKey)) {
            __weak UIView *weakBar = bar;
            if (SGRObserveLayout(title, ^(UIView *view) { if (weakBar) update(weakBar); })) {
                objc_setAssociatedObject(title, &kTitleWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }

    UIView *backdrop = backdropOf(bar);
    if (backdrop) {
        sg_backdrop = backdrop;
        if (!sg_emptyMask) sg_emptyMask = [CALayer layer];
        if (backdrop.layer.mask != sg_emptyMask) backdrop.layer.mask = sg_emptyMask;
        objc_setAssociatedObject(backdrop, &kBackdropMaskKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    static BOOL logged;
    if (!logged && bar.window && backHost && title) {
        logged = YES;
        SGLog(@"redesign profile: bar %@, back %@, title \"%@\", blur %@", NSStringFromCGRect(bar.frame),
              NSStringFromCGRect(backHost.frame), label.text, backdrop ? @"masked" : @"not found");
    }
}

// What was dressed goes back to Spotify's: the glass off (SGRShowGlass) and the blur's mask off.
static void undress(void) {
    UIView *backHost = sg_backHost, *titleHost = sg_titleHost, *backdrop = sg_backdrop;
    if (!backHost && !titleHost && !backdrop) return;
    UIView *backGlass = backHost ? objc_getAssociatedObject(backHost, &kBackGlassKey) : nil;
    UIView *titleGlass = titleHost ? objc_getAssociatedObject(titleHost, &kTitleGlassKey) : nil;
    if (backGlass) SGRShowGlass(backGlass, NO);
    if (titleGlass) SGRShowGlass(titleGlass, NO);
    if (backdrop && backdrop.layer.mask == sg_emptyMask) backdrop.layer.mask = nil;
    sg_backHost = nil;
    sg_titleHost = nil;
    sg_backdrop = nil;
}

static void update(UIView *bar) {
    if (profileListOnTop(bar)) dress(bar);
    else undress();
}

%hook SPNavigationBar
- (void)layoutSubviews {
    %orig;
    update((UIView *)self);
}
%end

// UIKit rebuilds the bar's buttons and title while laying this view out, which is after the bar's own pass.
%hook _UINavigationBarContentView
- (void)layoutSubviews {
    %orig;
    UIView *bar = ((UIView *)self).superview;
    if ([bar isKindOfClass:NSClassFromString(@"SPNavigationBar")]) update(bar);
}
%end

%hook _TtC18Profile_CommonImpl25ProfileListViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UINavigationBar *bar = ((UIViewController *)self).navigationController.navigationBar;
    if (bar) { update(bar); [bar setNeedsLayout]; }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UINavigationBar *bar = ((UIViewController *)self).navigationController.navigationBar;
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (bar) update(bar);
        });
    }
}

// A swipe back that is let go comes back through here and viewWillAppear; the bar is looked at again either way.
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    UINavigationBar *bar = ((UIViewController *)self).navigationController.navigationBar;
    if (bar) [bar setNeedsLayout];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"SPNavigationBar", @"_UINavigationBarContentView", @"_TtC18Profile_CommonImpl25ProfileListViewController"]);
}
