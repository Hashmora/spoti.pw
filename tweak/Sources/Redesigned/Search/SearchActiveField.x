// Search redesign: the field once the Search tab is tapped and Spotify's own recents/results page
// takes over (Search_FeatureImpl.HeaderViewController) -- a different field from the one this
// directory already glasses (Redesigned/Navbar/SearchField.x's SearchHeaderFind.SearchBar, the pill
// before anything is typed). This one is id=SearchBarSearch, a
// _TtC13Search_ECMKitP33_4AAD529A9116A2BD7185A1FC1B0C084527MultilineSearchBarContainer 358x32 holding
// SearchBarSearch.TextField, a placeholder and SearchBarSearch.CancelButton. It becomes the same glass
// capsule as the pill it opened from.
//
// Spotify used to draw the container itself with no shape at all, which is what made it worth glassing;
// a build since (trees/continuous/24.txt 2026-09-26) now wraps the text field in a pill of its own, a
// plain UIView 304 of the container's 358pt, painted white at 10% and rounded to match. Left alone, that
// pill draws on top of the glass -- first among the container's subviews same as the glass is, but added
// after it on each of Spotify's own passes -- and narrower besides, so the glass showed past its edges: two
// rounded shapes, not one. Concealed by shape and paint rather than by exact colour: the pill is only
// 10% white, too faint for SGIsLightColor's own half-alpha floor, but SGIsVisibleColor (Core/SGViewTree.m)
// reads any paint that draws at all, and nothing else rounded lives in this container besides the glass.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static char kGlassKey;

static void concealOwnPill(UIView *bar, UIView *glass) {
    SGForEachView(bar, ^(UIView *v) {
        if (v == bar || v == glass || v.layer.cornerRadius < 1) return;
        if (SGIsVisibleColor(v.layer.backgroundColor)) v.backgroundColor = UIColor.clearColor;
    });
}

%hook _TtC13Search_ECMKitP33_4AAD529A9116A2BD7185A1FC1B0C084527MultilineSearchBarContainer
- (void)layoutSubviews {
    %orig;
    UIView *bar = (UIView *)self;
    CGSize size = bar.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    if (bar.backgroundColor != UIColor.clearColor) bar.backgroundColor = UIColor.clearColor;
    if (bar.layer.cornerRadius != size.height / 2) bar.layer.cornerRadius = size.height / 2;
    if (bar.layer.cornerCurve != kCACornerCurveContinuous) bar.layer.cornerCurve = kCACornerCurveContinuous;
    if (!bar.layer.masksToBounds) bar.layer.masksToBounds = YES;
    UIView *glass = SGRGlassCapsuleInside(bar, &kGlassKey, size, NO);
    concealOwnPill(bar, glass);
    static BOOL logged;
    if (!logged && bar.window) {
        logged = YES;
        SGLog(@"redesign search: active search field %@ in glass", NSStringFromCGRect(bar.bounds));
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC13Search_ECMKitP33_4AAD529A9116A2BD7185A1FC1B0C084527MultilineSearchBarContainer"]);
}
