// Redesign: "Find on this page" (Liked Songs and any other playlist). It is the plain system UISearchBar
// (id=PL.SearchViewController.SearchBar), not one of Spotify's Encore fields, and its field is a flat
// _UISearchBarSearchFieldBackgroundView, bg=#767680@0.24 r=10 (trees/continuous/3.txt). It becomes a glass
// capsule like the redesign's other search fields (Navbar/SearchField.x).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRLegacyGlass.h"

static char kBoxKey, kGlassKey;

// The search field's own background view: Apple's private class, found by name since its identifier is
// nothing and its class isn't exported to link against.
static UIView *searchFieldBoxIn(UIView *bar) {
    UIView *cached = objc_getAssociatedObject(bar, &kBoxKey);
    if (cached && cached.superview) return cached;
    __block UIView *found = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (!found && [NSStringFromClass(v.class) containsString:@"SearchBarSearchFieldBackgroundView"]) found = v;
    });
    if (found) objc_setAssociatedObject(bar, &kBoxKey, found, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return found;
}

%hook SPTSearchBar
- (void)layoutSubviews {
    %orig;
    UIView *bar = (UIView *)self;
    if (![bar.accessibilityIdentifier isEqualToString:@"PL.SearchViewController.SearchBar"]) return;
    SGRGlassFlatBox(searchFieldBoxIn(bar), &kGlassKey);
    static BOOL logged;
    if (!logged && bar.window) {
        logged = YES;
        SGLog(@"redesign playlist: find-on-page search bar %@ in glass", NSStringFromCGRect(bar.bounds));
    }
}
%end

%ctor {
    if (!SGRedesignedUI() || !SGBelowIOS26()) return;
    %init;
    SGRequireClasses(@[@"SPTSearchBar"]);
}
