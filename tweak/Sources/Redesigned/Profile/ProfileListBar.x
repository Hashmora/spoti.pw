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
// only while a profile list is the page on top, and put back as it leaves. UIKit may build the bar's buttons again
// whenever the item changes, so the dressing is redone on every layout pass of the bar rather than once.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Profile.h"

// The glass is as tall as the round buttons beside it on the playlist's pages; the name has this much on each side.
static const CGFloat kGlassHeight = 44, kTitlePadding = 18;

static char kBackGlassKey, kTitleGlassKey, kBackdropWasKey;

// The profile list on top, and what was dressed for it, to be put back when it is not.
static __weak UIViewController *sg_onTop;
static __weak UIView *sg_backHost;
static __weak UIView *sg_titleHost;
static __weak UIView *sg_backdrop;

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
        UIView *glass = SGRGlassCapsuleInside(title, &kTitleGlassKey, CGSizeMake(width, kGlassHeight), NO);
        if (glass) SGRShowGlass(glass, YES);
        sg_titleHost = title;
    }

    UIView *backdrop = backdropOf(bar);
    if (backdrop) {
        if (sg_backdrop != backdrop) {
            sg_backdrop = backdrop;
            objc_setAssociatedObject(backdrop, &kBackdropWasKey, @(backdrop.layer.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!backdrop.layer.hidden) backdrop.layer.hidden = YES;
    }

    static BOOL logged;
    if (!logged && bar.window && backHost && title) {
        logged = YES;
        SGLog(@"redesign profile: bar %@, back %@, title \"%@\", blur %@", NSStringFromCGRect(bar.frame),
              NSStringFromCGRect(backHost.frame), label.text, backdrop ? @"hidden" : @"not found");
    }
}

// What was dressed goes back to Spotify's: the glass off (by its effect, SGRShowGlass) and the blur where it was.
static void undress(void) {
    UIView *backHost = sg_backHost, *titleHost = sg_titleHost, *backdrop = sg_backdrop;
    if (!backHost && !titleHost && !backdrop) return;
    UIView *backGlass = backHost ? objc_getAssociatedObject(backHost, &kBackGlassKey) : nil;
    UIView *titleGlass = titleHost ? objc_getAssociatedObject(titleHost, &kTitleGlassKey) : nil;
    if (backGlass) SGRShowGlass(backGlass, NO);
    if (titleGlass) SGRShowGlass(titleGlass, NO);
    if (backdrop) {
        NSNumber *was = objc_getAssociatedObject(backdrop, &kBackdropWasKey);
        if (backdrop.layer.hidden != was.boolValue) backdrop.layer.hidden = was.boolValue;
    }
    sg_backHost = nil;
    sg_titleHost = nil;
    sg_backdrop = nil;
}

static void update(UIView *bar) {
    UIViewController *page = sg_onTop;
    if (page && page.viewIfLoaded.window) dress(bar);
    else undress();
}

%hook SPNavigationBar
- (void)layoutSubviews {
    %orig;
    update((UIView *)self);
}
%end

%hook _TtC18Profile_CommonImpl25ProfileListViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sg_onTop = (UIViewController *)self;
    UINavigationBar *bar = ((UIViewController *)self).navigationController.navigationBar;
    if (bar) { update(bar); [bar setNeedsLayout]; }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sg_onTop = (UIViewController *)self;
    UINavigationBar *bar = ((UIViewController *)self).navigationController.navigationBar;
    if (bar) update(bar);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (sg_onTop == (UIViewController *)self) sg_onTop = nil;
    UINavigationBar *bar = ((UIViewController *)self).navigationController.navigationBar;
    if (bar) { update(bar); [bar setNeedsLayout]; }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"SPNavigationBar", @"_TtC18Profile_CommonImpl25ProfileListViewController"]);
}
