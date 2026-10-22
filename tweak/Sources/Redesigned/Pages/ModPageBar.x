// The mod's own pages under the redesign, iOS < 26: Mod Settings and every page SGModPage draws, the bar of Listening
// stats' over them (Pages/PageBar.m).
//
// Tree (trees/continuous/8.txt): the page is a UITableView the size of the screen on #000000, directly on
// the SPNavigationController's stack (no hosting controller), so the list already runs under the bar. Over it
// the navigation controller's blur (a plain 390x91 view holding a UIVisualEffectView), then SPNavigationBar with
// Back, the title ("Vitrine") and an empty trailing stack. So the blur goes, Back is pinned to the page as a glass
// circle and the title sits on a glass capsule; there is no ⋯ to carry (SGRDressBarPageBackOnly).
//
// The page is the mod's own, so it dresses its own bar (SGDressPageBar, called from SGModPage's passes) instead of
// being found by a hook on Spotify's controllers. The bar's own passes are watched too: UIKit makes its Back and
// title again after the page's pass, as for the hosted pages (Kit/SGRPlainBar.x).
//
// The page is a table, so the glass Back is a subview of what scrolls; SGModPage calls this again as the table
// moves, which puts the circle back at the top of the screen (SGRPinnedBackOf places it from the window).
//
// A page presented in a stack of its own (SGShowPage's fallback, the pickers, the lyrics style sheet) has no
// SPNavigationBar and is left as it is.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Settings/SGModPage.h"
#import "Pages.h"

static BOOL onSpotifyStack(UIViewController *page) {
    static Class stack;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ stack = NSClassFromString(@"SPNavigationController"); });
    return stack && [page.navigationController isKindOfClass:stack];
}

static BOOL redesignBars(void) {
    return SGRedesignedUI() && SGBelowiOS26();
}

void SGDressPageBar(UIViewController *page) {
    if (!redesignBars() || !onSpotifyStack(page)) return;
    SGRDressBarPageBackOnly(page);
}

void SGUndressPageBar(UIViewController *page) {
    if (!redesignBars() || !onSpotifyStack(page)) return;
    SGRUndressBarPage(page);
}

static void barPass(UIView *bar) {
    if (!redesignBars()) return;
    UIViewController *top = SGRNavigationOf(bar).topViewController;
    if ([top isKindOfClass:SGModPage.class] && top.viewIfLoaded.window) SGDressPageBar(top);
}

%hook SPNavigationBar
- (void)layoutSubviews {
    %orig;
    barPass((UIView *)self);
}
%end

// UIKit builds the bar's Back and title again while laying this view out, which is after the bar's own pass.
%hook _UINavigationBarContentView
- (void)layoutSubviews {
    %orig;
    UIView *bar = ((UIView *)self).superview;
    if ([bar isKindOfClass:NSClassFromString(@"SPNavigationBar")]) barPass(bar);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"SPNavigationBar", @"_UINavigationBarContentView"]);
    // Spotify's blur behind the bar is kept off from the push, not from the page's first pass.
    SGRRegisterBarPages(^BOOL(UIViewController *top) {
        return [top isKindOfClass:SGModPage.class] && onSpotifyStack(top);
    });
}
