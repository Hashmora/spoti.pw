// Redesign: "Find on this page" (Liked Songs and any other playlist). It is the plain system UISearchBar
// (id=PL.SearchViewController.SearchBar), not one of Spotify's Encore fields, and its field is a flat
// _UISearchBarSearchFieldBackgroundView, bg=#767680@0.24 r=10. It becomes a glass
// capsule like the redesign's other search fields (Navbar/SearchField.x). The bar's opaque backing goes so the
// glass has the page behind it, and the Cancel button on the right is glass too.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static char kBoxKey, kGlassKey, kCancelKey;

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

// The bar's own backing. A UISearchBar paints a bar background (_UIBarBackground / UISearchBarBackground,
// an image and a blur) behind the field, and Spotify puts the page's base black on the bar and on the
// view that holds it. The glass capsule blurs what is behind it, so a black plate there leaves it
// nothing to show: the plate goes, the bar stays minimal and the field's glass sees the page.
static void clearBarBacking(UIView *bar) {
    UISearchBar *search = (UISearchBar *)bar;
    if (search.searchBarStyle != UISearchBarStyleMinimal) search.searchBarStyle = UISearchBarStyleMinimal;
    if (search.backgroundImage) search.backgroundImage = nil;
    if (search.barTintColor) search.barTintColor = nil;
    if (bar.backgroundColor && bar.backgroundColor != UIColor.clearColor) bar.backgroundColor = UIColor.clearColor;
    SGForEachView(bar, ^(UIView *v) {
        NSString *name = NSStringFromClass(v.class);
        if ([name containsString:@"BarBackground"] || [name containsString:@"SearchBarBackground"]) {
            if (v.alpha != 0) v.alpha = 0;
            return;
        }
        // Only an opaque fill that is the page's black or an effect plate: never the field's own box.
        if (v != bar && ![name containsString:@"SearchFieldBackgroundView"] && v.backgroundColor
            && SGIsBaseSurface(v.backgroundColor.CGColor)) {
            v.backgroundColor = UIColor.clearColor;
        }
    });
    // The wrappers above it, up to the page: the container Spotify puts the bar in paints the same black.
    for (UIView *up = bar.superview; up && up != sgr_playlistRoot; up = up.superview) {
        if ([up isKindOfClass:UIScrollView.class]) break;
        if (up.backgroundColor && SGIsBaseSurface(up.backgroundColor.CGColor)) up.backgroundColor = UIColor.clearColor;
    }
}

// Cancel, which the bar shows from the moment the field is entered: a plain UIButton Apple builds
// (UINavigationButton) with a title, found by being the one button with a text, and given the same
// glass capsule as the field. The capsule is drawn a little wider than the button -- the button hugs its
// text -- and the control's own clipping is left alone, so the glass goes past the frame by the padding.
static UIButton *cancelButtonIn(UIView *bar) {
    __block UIButton *found = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (found || ![v isKindOfClass:UIButton.class]) return;
        UIButton *button = (UIButton *)v;
        if (button.currentTitle.length || button.titleLabel.text.length) found = button;
    });
    return found;
}

static void glassCancel(UIView *bar) {
    UIButton *cancel = cancelButtonIn(bar);
    CGSize size = cancel.bounds.size;
    if (!cancel || cancel.hidden || size.width < 1 || size.height < 1) return;
    CGFloat height = MIN(size.height, 36);
    UIView *glass = SGRGlassCapsuleInside(cancel, &kCancelKey, CGSizeMake(size.width + 20, height), NO);
    glass.layer.cornerRadius = height / 2;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
    [cancel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [cancel setTitleColor:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateHighlighted];
    cancel.clipsToBounds = NO;
}

%hook SPTSearchBar
- (void)layoutSubviews {
    %orig;
    UIView *bar = (UIView *)self;
    if (![bar.accessibilityIdentifier isEqualToString:@"PL.SearchViewController.SearchBar"]) return;
    clearBarBacking(bar);
    SGRGlassFlatBox(searchFieldBoxIn(bar), &kGlassKey);
    glassCancel(bar);
    static BOOL logged;
    if (!logged && bar.window) {
        logged = YES;
        SGLog(@"redesign playlist: find-on-page search bar %@ in glass", NSStringFromCGRect(bar.bounds));
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (@available(iOS 26.0, *)) return;   // from iOS 26 the system draws its own glass; this is the legacy glass's
    %init;
    SGRequireClasses(@[@"SPTSearchBar"]);
}
