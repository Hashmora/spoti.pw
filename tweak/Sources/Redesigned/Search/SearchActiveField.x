// Search redesign: the field once the Search tab is tapped and Spotify's own recents/results page
// takes over (Search_FeatureImpl.HeaderViewController) -- a different field from the one this
// directory already glasses (Redesigned/Navbar/SearchField.x's SearchHeaderFind.SearchBar, the pill
// before anything is typed). This one is id=SearchBarSearch, a
// _TtC13Search_ECMKitP33_4AAD529A9116A2BD7185A1FC1B0C084527MultilineSearchBarContainer 358x32 holding
// SearchBarSearch.TextField, a placeholder and SearchBarSearch.CancelButton (trees/continuous/24.txt
// 2026-09-26); Spotify draws the container itself with no shape at all, so nothing was there for the
// Kit's own capsule to replace and it stayed square. It becomes the same glass capsule as the pill it
// opened from.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static char kGlassKey;

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
    SGRGlassCapsuleInside(bar, &kGlassKey, size, NO);
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
