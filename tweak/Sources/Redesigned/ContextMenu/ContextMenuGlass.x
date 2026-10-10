// Glass for UIKit's own context menus: the player's ⋯ menu (the row of Add to playlist / Share / Add to Queue
// over the list, Speed and the rest) and every other menu Spotify opens the same way. ContextMenu.x makes the
// menu; this is only its look. (Taken from the pure-glass branch.)
//
// Tree (trees/continuous/2.txt, 2026-10-09): _UIContextMenuContainerView > _UIContextMenuPlatterTransitionView >
// _UIContextMenuView > _UIContextMenuListView, one for the menu and one more for a submenu, each holding a
// _UICutoutShadowView and a clipping UIView (the platter) with UIKit's own UIVisualEffectView and the menu's
// UICollectionView in it. The platter's blur is hidden and a glass pane, the heavy kind a sheet gets
// (SGRThickenSheetGlass), goes behind its content. The labels are drawn #000000@0.96, the light appearance the
// menu takes from a phone in light mode, so the list is made dark like the rest of the glass.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

// The corners UIKit cuts a menu with.
static const CGFloat kMenuRadius = 14;
// The black laid over the glass: the light body alone leaves white labels too little contrast.
static const CGFloat kMenuDim = 0.42;
static char kMenuGlassKey;

// The clipping view holding UIKit's blur: the menu's own surface.
static UIView *platterIn(UIView *list) {
    for (UIView *sub in list.subviews) {
        if (object_getClass(sub) != UIView.class || !sub.clipsToBounds) continue;
        for (UIView *inner in sub.subviews) {
            if (object_getClass(inner) == UIVisualEffectView.class) return sub;
        }
    }
    return nil;
}

static void glassMenu(UIView *list) {
    UIView *platter = platterIn(list);
    if (!platter || platter.bounds.size.width < 1 || platter.bounds.size.height < 1) return;
    if (list.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) list.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    UIView *glass = SGGlassFor(platter, &kMenuGlassKey);
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (!CGRectEqualToRect(glass.frame, platter.bounds)) glass.frame = platter.bounds;
    SGShapeGlass(glass, kMenuRadius, NO);
    SGRThickenSheetGlass(glass, kMenuRadius);
    SGRDimSheetGlass(glass, kMenuDim);

    // UIKit's own blur goes; the pane above is the mod's, which is a UIVisualEffectView too when it is not
    // the legacy glass.
    for (UIView *sub in platter.subviews) {
        if (sub != glass && object_getClass(sub) == UIVisualEffectView.class && !sub.hidden) sub.hidden = YES;
    }

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"context menu: glass over a platter of %@", NSStringFromCGRect(platter.bounds)); });
}

%hook _UIContextMenuListView
- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) glassMenu((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    glassMenu((UIView *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_UIContextMenuListView"]);
}
