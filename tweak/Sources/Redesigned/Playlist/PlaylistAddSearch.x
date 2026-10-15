// Playlist redesign, iOS < 26: the Add songs sheet's own search (the "What would you like to add?" page behind the
// Add songs row, and the Find page it opens) on glass, the way the Search tab's field is.
//
// Tree (trees/continuous/13.txt:2249-2257, 14.txt:2188-2200): a plain UIView 358x48 bg=#282828 r=24
// id=AssistedCuration.SearchBar, pinned over the bottom of the sheet inside an AssistedCurationSearchBarElement, holding
// the magnifier, the label (on the Find page the text field) and the clear button. It is the grey box a search field is
// elsewhere in the redesign, so it gets the same glass (SGRGlassFlatBox): cleared, round, glass inside it, its
// contents above. Spotify paints the grey again as the field is focused, so SGRRepaint.x keeps it clear
// (sgr_addSongsSearchBar).
//
// The Find page's navigation bar (14.txt:2230-2250) is UIKit's: a _UIButtonBarButton with a bare chevron
// (_UIModernBarButton) and the title. Its Back gets a glass circle, the one the playlist, album and artist pages
// and the profile lists give theirs (Profile/ProfileListBar.x). The bar belongs to the sheet's own
// navigation controller (AssistedCuration_PageImpl.AssistedCurationNavigationController), so nothing is put back: the
// button, and the glass in it, go with the page. UIKit builds the buttons again while it lays the content view out,
// after the bar's own pass, so the dressing runs from both.
//
// The chips of the Find page (Songs / Artists / Albums) are the library's FilterChipView: Library/LibraryHeader.x
// gives them their glass (inLibraryChips takes this row too).
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRRepaint.h"

// As tall as the round buttons beside it on the playlist's pages (Profile/ProfileListBar.x).
static const CGFloat kBackGlassHeight = 44;

static char kBarKey, kBarGlassKey, kBackGlassKey;

// A Swift class by module and name, under the mangled spelling or the dotted one the trees print; nil when the
// app has neither.
static Class swiftClass(NSString *module, NSString *name) {
    NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@", (unsigned long)module.length, module, (unsigned long)name.length, name];
    return NSClassFromString(mangled) ?: NSClassFromString([NSString stringWithFormat:@"%@.%@", module, name]);
}

#pragma mark - the search bar

static void glassSearchBar(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (!root || root.bounds.size.width < 1) return;
    UIView *bar = SGRFindByIdentifier(root, @"AssistedCuration.SearchBar", &kBarKey);
    if (!bar || bar.bounds.size.height < 1) return;
    if (sgr_addSongsSearchBar != bar) sgr_addSongsSearchBar = bar;
    if (bar.layer.backgroundColor) bar.layer.backgroundColor = NULL;
    SGRGlassFlatBox(bar, &kBarGlassKey);

    static BOOL logged;
    if (!logged && bar.window) {
        logged = YES;
        SGLog(@"redesign playlist: add songs search bar %@ in glass", NSStringFromCGRect(bar.bounds));
    }
}

// The bar is made after the page's first layout, and its grey comes back with the rows.
static void searchBarPasses(UIViewController *controller) {
    __weak UIViewController *weak = controller;
    glassSearchBar(controller);
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) glassSearchBar(weak);
        });
    }
}

%group SGRAddSongsRecommendations
%hook SGRRecommendations
- (void)viewDidLayoutSubviews {
    %orig;
    glassSearchBar((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    searchBarPasses((UIViewController *)self);
}
%end
%end

%group SGRAddSongsFind
%hook SGRFind
- (void)viewDidLayoutSubviews {
    %orig;
    glassSearchBar((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    searchBarPasses((UIViewController *)self);
}
%end
%end

#pragma mark - the Find page's Back

static UIView *subviewNamed(UIView *host, NSString *name) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:name]) return sub;
    }
    return nil;
}

static UINavigationController *navigationOf(UIView *bar) {
    for (UIResponder *r = bar; r; r = r.nextResponder) {
        if ([r isKindOfClass:UINavigationController.class]) return (UINavigationController *)r;
    }
    return nil;
}

static void glassBack(UIView *bar) {
    if (bar.bounds.size.width < 1) return;
    if (![NSStringFromClass(navigationOf(bar).class) containsString:@"AssistedCurationNavigationController"]) return;
    __block UIView *back = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (!back && [NSStringFromClass(v.class) isEqualToString:@"_UIButtonBarButton"] && subviewNamed(v, @"_UIBackButtonMaskView")) back = v;
    });
    // The glass goes in the control that draws the chevron, so the circle is centred on the glyph (the bar button
    // around it is 48pt wide and the glyph sits off its middle).
    UIView *host = back ? (subviewNamed(back, @"_UIModernBarButton") ?: back) : nil;
    if (!host || host.bounds.size.width < 1) return;
    UIView *glass = SGRGlassInside(host, &kBackGlassKey, kBackGlassHeight);
    if (glass) SGRShowGlass(glass, YES);

    static BOOL logged;
    if (!logged && bar.window) {
        logged = YES;
        SGLog(@"redesign playlist: find page back button %@ in glass", NSStringFromCGRect(host.frame));
    }
}

%group SGRAddSongsBar
%hook SPNavigationBar
- (void)layoutSubviews {
    %orig;
    glassBack((UIView *)self);
}
%end

// UIKit rebuilds the bar's buttons while laying this view out, which is after the bar's own pass.
%hook _UINavigationBarContentView
- (void)layoutSubviews {
    %orig;
    UIView *bar = ((UIView *)self).superview;
    if ([bar isKindOfClass:NSClassFromString(@"SPNavigationBar")]) glassBack(bar);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class recommendations = swiftClass(@"AssistedCuration_RecommendationsImpl", @"RecommendationsViewController");
    if (recommendations) {
        %init(SGRAddSongsRecommendations, SGRRecommendations = recommendations);
    } else {
        SGLog(@"class AssistedCuration_RecommendationsImpl.RecommendationsViewController not found, the add songs search keeps Spotify's grey");
    }
    Class find = swiftClass(@"AssistedCuration_SearchImpl", @"AssistedCurationSearchContainerViewController");
    if (find) {
        %init(SGRAddSongsFind, SGRFind = find);
    } else {
        SGLog(@"class AssistedCuration_SearchImpl.AssistedCurationSearchContainerViewController not found, the Find page's search keeps Spotify's grey");
    }
    if (NSClassFromString(@"SPNavigationBar") && NSClassFromString(@"_UINavigationBarContentView")) {
        %init(SGRAddSongsBar);
    }
}
