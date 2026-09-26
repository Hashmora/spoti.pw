// Redesign: "Find on this page" (Liked Songs and any other playlist), the plain system UISearchBar
// Spotify drops in over the list rather than one of its own Encore fields -- id=PL.SearchViewController.SearchBar,
// a bare SPTSearchBar around UISearchBarTextField's own _UISearchBarSearchFieldBackgroundView, a flat
// bg=#767680@0.24 r=10.0 (trees/continuous/3.txt 2026-09-26). Nothing in the redesign had ever touched
// it, so it stayed the one search field left as iOS draws it while every other one -- the Search tab's,
// the library's, Home's -- became a glass capsule (Redesigned/Navbar/SearchField.x, Library/LibrarySearch.x).
// It becomes the same capsule here, the field itself the control the glass goes inside (matching
// PlaylistHeader.x's glassUp for the toolbar's own field/sort boxes).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

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

static void glassSearchBar(UIView *bar) {
    UIView *box = searchFieldBoxIn(bar);
    CGSize size = box.bounds.size;
    if (!box || size.width < 1 || size.height < 1) return;
    if (box.backgroundColor != UIColor.clearColor) box.backgroundColor = UIColor.clearColor;
    if (box.layer.cornerRadius != size.height / 2) box.layer.cornerRadius = size.height / 2;
    if (box.layer.cornerCurve != kCACornerCurveContinuous) box.layer.cornerCurve = kCACornerCurveContinuous;
    if (!box.layer.masksToBounds) box.layer.masksToBounds = YES;
    SGRGlassCapsuleInside(box, &kGlassKey, size, NO);
}

%hook SPTSearchBar
- (void)layoutSubviews {
    %orig;
    UIView *bar = (UIView *)self;
    if (![bar.accessibilityIdentifier isEqualToString:@"PL.SearchViewController.SearchBar"]) return;
    glassSearchBar(bar);
    static BOOL logged;
    if (!logged && bar.window) {
        logged = YES;
        SGLog(@"redesign playlist: find-on-page search bar %@ in glass", NSStringFromCGRect(bar.bounds));
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"SPTSearchBar"]);
}
