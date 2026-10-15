// Redesign, iOS < 26: the pages that sit under UIKit's own navigation bar instead of drawing a header of
// their own -- Chapters (Show all of an episode's Chapters), Listening stats and its Top artists and Top
// songs, a track or an artist opened from them, Your Premium and its Manage subscription, and SongDNA (its Share and Close pinned as glass circles, 37.txt). Each is a controller
// hosted by Navigation_PageAPIIntegrationImpl.MusicAppPageHostingViewController (trees/continuous/9 to 13, 18).
//
// The bar is dressed by Pages/PageBar.m, as Recents' and Your Updates' are: Spotify's blur behind it drawn by
// nothing, its Back and its Share pinned to the page as glass circles at the corners, the title on a glass
// capsule in white. Pinned, and not a glass put inside the bar's own buttons: the Back of the bar is UIKit's, and
// the swipe back moves its chevron and its mask about and builds it again, so a circle inside it ended up on
// one layer with the chevron on another, under it and off centre (device, 2026-10-15, trees/continuous/9.txt,
// 11.txt). The chevron the bar draws sits 6pt left of the middle of its button besides.
//
// It is dressed from the bar's own layout passes as well as the page's: the page's child controller is made once
// its data has loaded, which no pass of the hosting controller follows, so a page opened at the top of its list
// showed Spotify's bar until it was scrolled (9.txt).
//
// Its blur is kept off from the push (SGRSyncBarBlur, Pages/PageAppearance.x), not from the first pass that finds the bar.
//
// And the page itself is made dark. Under the redesign these lists drew a white UICollectionView under
// their white labels until the app was left and entered again (device, 2026-10-14), so every hosted page
// is given the dark appearance, which Spotify has everywhere, and the two Stats lists are cleared of the
// white they were painted. Manage subscription paints a black band as high as the bar over its list
// (13.txt:100), which is drawn by nothing here.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Pages/Pages.h"

static Class sg_hosting;

// A part of the name of a page's own controller, below the hosting one.
static NSArray<NSString *> *pageMarkers(void) {
    return @[@"EntitySegmentsViewController", @"UserTimelineViewController", @"StatsDetailsViewController",
             @"YourPremiumViewController", @"PlanOverviewViewController", @"SongDNAViewController"];
}

static BOOL isPage(UIViewController *controller, int depth) {
    if (depth > 6) return NO;
    for (UIViewController *child in controller.childViewControllers) {
        NSString *name = NSStringFromClass(child.class);
        for (NSString *marker in pageMarkers()) {
            if ([name containsString:marker]) return YES;
        }
        if (isPage(child, depth + 1)) return YES;
    }
    return NO;
}

// The white UICollectionView Spotify's Stats lists paint.
static void clearStatsLists(UIView *root) {
    SGForEachView(root, ^(UIView *v) {
        if (![v isKindOfClass:UICollectionView.class]) return;
        if (![v.accessibilityIdentifier hasSuffix:@"ViewController.CollectionView"]) return;
        if (![v.accessibilityIdentifier hasPrefix:@"UserTimeline"] && ![v.accessibilityIdentifier hasPrefix:@"StatsDetails"]) return;
        if (v.backgroundColor && ![v.backgroundColor isEqual:UIColor.clearColor]) v.backgroundColor = UIColor.clearColor;
    });
}

// The black band over the top of Manage subscription's list: a plain childless view at the top of the page, as wide
// as it and as high as the bar, painted the page black. An empty mask, which Spotify's painting it again does not undo.
static void clearTopBand(UIView *root) {
    CGFloat width = root.bounds.size.width;
    SGForEachView(root, ^(UIView *v) {
        if (v == root || ![v isMemberOfClass:UIView.class] || v.subviews.count || v.layer.mask) return;
        CGRect frame = v.frame;
        if (fabs(frame.origin.y) > 0.5 || fabs(frame.size.width - width) > 1 || frame.size.height < 40 || frame.size.height > 140) return;
        CGColorRef color = v.layer.backgroundColor;
        if (!color || !SGIsBaseSurface(color)) return;
        v.layer.mask = [CALayer layer];
        if (v.userInteractionEnabled) v.userInteractionEnabled = NO;
    });
}

static void dress(UIViewController *page) {
    UIView *root = page.viewIfLoaded;
    if (root.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) root.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if (!isPage(page, 0)) return;
    clearStatsLists(root);
    clearTopBand(root);
    if (!SGBelowiOS26()) return;
    SGRDressBarPage(page);
}

static void undress(UIViewController *page) {
    if (!SGBelowiOS26() || !isPage(page, 0)) return;
    SGRUndressBarPage(page);
}

static UINavigationController *navigationOf(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if ([r isKindOfClass:UINavigationController.class]) return (UINavigationController *)r;
    }
    return nil;
}

%group SGRPlainBarPages
%hook SGRHostingController
- (void)viewDidLoad {
    %orig;
    UIView *root = ((UIViewController *)self).viewIfLoaded;
    if (root.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) root.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}

- (void)viewDidLayoutSubviews {
    %orig;
    dress((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dress((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    for (NSNumber *delay in @[@0.0, @0.25, @0.6, @1.2, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak && weak.viewIfLoaded.window) dress(weak);
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    undress((UIViewController *)self);
}
%end

// The bar's own passes: the page on top of its navigation controller, if it is one of these, is dressed.
static void barPass(UIView *bar) {
    if (!SGBelowiOS26()) return;
    UINavigationController *navigation = navigationOf(bar);
    SGRSyncBarBlur(navigation);
    UIViewController *top = navigation.topViewController;
    if (top && [top isKindOfClass:sg_hosting] && top.viewIfLoaded.window) dress(top);
}

%hook SPNavigationBar
- (void)layoutSubviews {
    %orig;
    barPass((UIView *)self);
}
%end

// UIKit builds the bar's Back and title again as Spotify sets the page's item, which for these pages is when its data
// has loaded and while this view is laid out, after the bar's own pass: Spotify's bar showed until the next pass of
// the bar, a scroll, and the redesign's came only then (trees/continuous/14.txt).
%hook _UINavigationBarContentView
- (void)layoutSubviews {
    %orig;
    UIView *bar = ((UIView *)self).superview;
    if ([bar isKindOfClass:NSClassFromString(@"SPNavigationBar")]) barPass(bar);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    Class hosting = SGRPageClass(@"Navigation_PageAPIIntegrationImpl", @"MusicAppPageHostingViewController");
    if (!hosting) {
        SGLog(@"class Navigation_PageAPIIntegrationImpl.MusicAppPageHostingViewController not found, Chapters, Listening stats, Your Premium and Manage subscription keep Spotify's bar");
        return;
    }
    sg_hosting = hosting;
    // A hosted page whose own controller has not been made yet is taken for one of these: its blur stays off from the push,
    // and is given back at the next pass if the page turns out to be another.
    if (SGBelowiOS26()) {
        SGRRegisterBarPages(^BOOL(UIViewController *top) {
            return [top isKindOfClass:hosting] && (!top.childViewControllers.count || isPage(top, 0));
        });
    }
    %init(SGRPlainBarPages, SGRHostingController = hosting);
}
