// The side drawer (the avatar on Home, Search or Your Library): Spotify draws it as a panel painted #1F1F1F the height of
// the screen, with each row's own fill under it, the only gray surface left in the redesign (the phone, 2026-10-23).
// Here the panel is a pane of the sheets' glass with the screen's corners, and the rows' fills go, so the rows sit on it.
//
// Tree (the phone, 2026-10-23): over SideDrawerPresentationController's dimming view, an ElementView of
// SideDrawer_ListPageImpl.SideDrawerElement 372.5x896 whose first subview is the panel (bg #1F1F1F) holding the profile
// header and SideDrawerListCollectionView, whose rows are Encore ListRows that draw their fill as a CAShapeLayer the
// size of the row.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static char kDrawerGlassKey;

// The panel: the first subview of the drawer's element view.
static UIView *panelIn(UIView *root) {
    __block UIView *panel = nil;
    SGForEachView(root, ^(UIView *v) {
        if (panel || ![NSStringFromClass(v.class) containsString:@"SideDrawerElement5State"]) return;
        panel = v.subviews.firstObject;
    });
    return panel;
}

// A row's fill: a shape layer the size of the row, with a visible fill. The press highlight beside it is inset and at
// opacity 0, and stays.
static void clearRowFill(UIView *row) {
    CGRect bounds = row.layer.bounds;
    for (CALayer *layer in row.layer.sublayers) {
        if (![layer isKindOfClass:CAShapeLayer.class] || !CGRectEqualToRect(layer.frame, bounds)) continue;
        CAShapeLayer *fill = (CAShapeLayer *)layer;
        if (fill.fillColor && CGColorGetAlpha(fill.fillColor) > 0) fill.fillColor = UIColor.clearColor.CGColor;
    }
}

static void dress(UIViewController *controller) {
    UIView *panel = panelIn(controller.viewIfLoaded);
    if (!panel || panel.bounds.size.width < 1) return;
    SGRGlassPaneIn(panel, &kDrawerGlassKey, SGRSheetCornerRadius());
    if (SGIsVisibleColor(panel.layer.backgroundColor)) panel.backgroundColor = UIColor.clearColor;
    SGForEachView(panel, ^(UIView *v) {
        if ([NSStringFromClass(v.class) hasSuffix:@"Encore7ListRow"]) clearRowFill(v);
    });
}

%ctor {
    if (!SGRedesignedUI()) return;
    SGRPassSwiftController(@"SideDrawer_ListPageImpl", @"ListViewController", ^(UIViewController *c) { dress(c); });
}
