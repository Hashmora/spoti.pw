// Library redesign: the search inside the library, the page the header's magnifier opens.
//
// Tree: YourLibrarySearchView holds the same YourLibraryContentView and list
// as the library itself, and over them YourLibrarySearchHeaderView 402x142 -- LiquidGlass.GradientView (the
// scrim) and, at {0, 94}, a SearchHeaderLibraryLayout of two shapes 32pt tall: the field,
// id=Components.Header.UI.Toolbar.SearchField 320x32 r=4, and id=Components.Header.UI.Toolbar.ButtonContainer
// 58x32 r=4 around Cancel. Both already draw Reprise_LiquidGlassKit's LiquidGlass.SearchBarView inside
// themselves, so there is nothing to put behind them: what Spotify's own glass is missing here is the shape.
// They become capsules, which is the shape the Search tab's field has (Redesigned/Navbar/SearchField.x), and
// the scrim goes the way it goes on every other redesigned page.
//
// The header is 142pt and holds no filter chips, so there is nothing here to close up: LibraryHeader.x shrinks
// a header only where chips leave a band behind.
//
// Below iOS 26 the field and Cancel hold no glass of Spotify's (trees/continuous/11.txt: the field a flat
// #FFFFFF@0.14 box, Cancel a grey label), so they get the glass every other search field of the redesign has
// (SGRGlassFlatBox); Spotify paints the field's grey again as it is focused, which SGRRepaint.x keeps clear
// (sgr_showSearchField). Cancel's label stands in a 40pt button at the trailing end of a 48pt box, 8pt in, so its
// capsule is made inside that button, wider than it, and the boxes above stop clipping for it.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "Library.h"

static char kFieldKey, kCancelKey, kCancelButtonKey, kFieldGlassKey, kCancelGlassKey;

// Room Cancel's capsule takes beside its label on each side, and its height (the field's).
static const CGFloat kCancelPadding = 10, kCancelHeight = 32;

static UIView *childNamed(UIView *host, NSString *marker) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) containsString:marker]) return sub;
    }
    return nil;
}

static void capsule(UIView *shape) {
    CGFloat height = shape.bounds.size.height;
    if (height < 24) return;
    CALayer *layer = shape.layer;
    if (layer.cornerRadius != height / 2) layer.cornerRadius = height / 2;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
    if (!layer.masksToBounds) layer.masksToBounds = YES;
}

// The field and Cancel on glass, below iOS 26.
static void glassSearch(UIView *page, UIView *field, UIView *cancel) {
    if (field) {
        if (sgr_showSearchField != field) sgr_showSearchField = field;
        SGRGlassFlatBox(field, &kFieldGlassKey);
    }
    UIView *button = cancel ? SGRFindByIdentifier(cancel, @"Components.Header.UI.Toolbar.Button", &kCancelButtonKey) : nil;
    if (!button || button.bounds.size.width < 1 || button.bounds.size.height < 1) return;
    // Cancel's boxes clip to their own bounds, and the capsule is wider than the button.
    for (UIView *v = button; v && v != page && v != field.superview; v = v.superview) {
        if (v.clipsToBounds) v.clipsToBounds = NO;
    }
    SGRGlassCapsuleInside(button, &kCancelGlassKey, CGSizeMake(button.bounds.size.width + 2 * kCancelPadding, kCancelHeight), NO);
}

%hook _TtC28YourLibrary_YourLibraryXImpl21YourLibrarySearchView
- (void)layoutSubviews {
    %orig;
    UIView *header = childNamed((UIView *)self, @"YourLibrarySearchHeaderView");
    if (!header) return;
    SGRLibraryClearScrim(header);
    UIView *field = SGRFindByIdentifier(header, @"Components.Header.UI.Toolbar.SearchField", &kFieldKey);
    UIView *cancel = SGRFindByIdentifier(header, @"Components.Header.UI.Toolbar.ButtonContainer", &kCancelKey);
    if (SGBelowiOS26()) {
        glassSearch((UIView *)self, field, cancel);
    } else {
        capsule(field);
        capsule(cancel);
    }

    // The first pass the field had a size on: before that there is no shape to report.
    static BOOL logged;
    if (!logged && field.bounds.size.height > 1) {
        logged = YES;
        SGLog(@"redesign library: search field %@ at r=%.1f, cancel %@", NSStringFromCGRect(field.bounds),
              field.layer.cornerRadius, cancel ? @"a capsule too" : @"not found");
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC28YourLibrary_YourLibraryXImpl21YourLibrarySearchView"]);
}
