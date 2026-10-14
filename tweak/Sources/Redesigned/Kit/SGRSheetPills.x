// Redesign, iOS < 26: the chips of the Add to playlist sheet on glass, as the library's chips are.
//
// Tree (trees/continuous/27.txt:1250-1290): the sheet's AssistedCurationTabsElement holds a
// Home_PillUIKit.PillScrollView, a UIScrollView of PillDrawerViews, each with a Home_PillUIKit.PillView 32pt
// tall (From your Liked Songs, Recently played, Songs). The pill paints its own layer, #333333 unselected and a
// solid colour of its own (the accent) selected, so, unlike Encore's chips (SGRChips.m), the unselected fill is
// an opaque grey and not a translucent white.
//
// The glass goes in the pill itself, first among its subviews, as in the library (Library/LibraryHeader.x): an
// unselected pill's grey goes and a glass capsule stands behind its label; a selected pill keeps its colour, and
// its glass is hidden so no rim shows round the edge. Spotify paints the pill again as it is selected and let
// go, which lays nothing out, so SGRRepaint.x keeps the grey off a dressed pill and tells it (SGRIsSheetPill,
// SGRSheetPillPainted).
//
// Only the pills inside a sheet (id=sheet-view): Home's own PillScrollView is not dressed here.
#import "Core/SGCore.h"
#import "SGRChips.h"
#import "SGRGlass.h"

static char kPillGlassKey, kPillDressedKey;
// Set once a pill has been dressed: until then SGRRepaint.x's hook, which hears every layer's paint, does no lookup.
static BOOL sLive;

static BOOL inSheet(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:@"sheet-view"]) return YES;
    }
    return NO;
}

// The flat grey Spotify paints an unselected pill with: opaque, neutral, dark. A selected pill is a colour or a
// bright one, never this.
BOOL SGRIsPillGrey(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID() || CGColorGetAlpha(color) < 0.05) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    if (n == 2) return c[0] <= 0.35;
    if (n < 3) return NO;
    return c[0] <= 0.35 && fabs(c[0] - c[1]) < 0.03 && fabs(c[1] - c[2]) < 0.03;
}

// A selected pill carries a paint that is not the grey and is solid.
static BOOL pillIsSelected(UIView *pill) {
    CGColorRef paint = pill.layer.backgroundColor;
    return paint && CGColorGetAlpha(paint) > 0.3 && !SGRIsPillGrey(paint);
}

// A pill grows under a finger with the legacy glass (SGGlassInteractive) and the scroll view it stands in clips to
// its bounds, which cut the grown capsule off at its edges. Every view from the pill up to the pill scroll view
// stops clipping; the row is as wide as the sheet, so nothing shows that was not on screen already.
static void unclipPill(UIView *pill) {
    if (!SGUseLegacyGlass()) return;
    for (UIView *v = pill.superview; v; v = v.superview) {
        if (v.clipsToBounds) v.clipsToBounds = NO;
        if ([NSStringFromClass(v.class) hasSuffix:@"PillScrollView"]) break;
    }
}

static void glassPill(UIView *pill) {
    CGSize size = pill.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    unclipPill(pill);
    if (pillIsSelected(pill)) {
        UIView *glass = objc_getAssociatedObject(pill, &kPillGlassKey);
        if (glass && !glass.hidden) glass.hidden = YES;
        return;
    }
    if (pill.layer.backgroundColor) pill.layer.backgroundColor = NULL;
    SGRGlassCapsuleInside(pill, &kPillGlassKey, size, NO);
}

static void dressPill(UIView *pill) {
    if (!pill.window || !inSheet(pill)) return;
    if (!objc_getAssociatedObject(pill, &kPillDressedKey)) {
        objc_setAssociatedObject(pill, &kPillDressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        sLive = YES;
        SGLog(@"sheet pills: glass over a pill of %@", NSStringFromCGRect(pill.bounds));
    }
    glassPill(pill);
}

BOOL SGRSheetPillsLive(void) {
    return sLive;
}

BOOL SGRIsSheetPill(UIView *view) {
    return objc_getAssociatedObject(view, &kPillDressedKey) != nil;
}

void SGRSheetPillPainted(UIView *pill) {
    if (pill.window && SGRIsSheetPill(pill)) glassPill(pill);
}

%group SGRSheetPills
%hook SGRPillView
- (void)layoutSubviews {
    %orig;
    dressPill((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    dressPill((UIView *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    // The class as the app has it: mangled, or dotted as the trees print it.
    Class pill = NSClassFromString(@"_TtC14Home_PillUIKit8PillView") ?: NSClassFromString(@"Home_PillUIKit.PillView");
    if (pill) {
        %init(SGRSheetPills, SGRPillView = pill);
    } else {
        SGLog(@"class Home_PillUIKit.PillView not found, the chips of the Add to playlist sheet keep Spotify's grey");
    }
}
