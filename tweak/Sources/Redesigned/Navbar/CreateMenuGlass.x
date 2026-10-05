// Redesign: glass for the two Create menus, the same pane the queue, the ⋯ menu and the Connect picker have
// (trees/continuous 2026-10-05: 1.txt and 2.txt of the Create dumps). Both draw the same three or four
// CreateMenuItemRows, but they are laid out differently, so each gets what fits it:
//
// - The tab bar's Create menu (CreateMenu_CreateMenuPageImpl) is a floating card, not a full sheet: the
//   sheet-view is 307 pt tall with no fill and reaches down over the tab bar, where the transparent
//   CreateMenu.ForwardingView hands touches to the Create tab that has turned into the close button. A pane
//   over the whole sheet-view would cover the tab bar, so the glass goes behind the card alone
//   (CreateMenu.ScrollView, #1F1F1F, r=16, inset 8 pt from the sides), and the card's own grey goes clear.
//   The pane is a sibling of the card rather than a subview of it, so it stays put when the card scrolls.
// - The Create playlist sheet from the Library's + (PlaylistCreation_SheetPageImpl) is an ordinary sheet:
//   id=sheet-view, #1F1F1F, full width, with the same rows in it. PGRGlassSheetChrome does all of it.
//
// The rows' icon circles (Encore.Box, #FFFFFF@0.14) are already translucent white and are left as they are.
#import "Core/PGCore.h"
#import "Redesigned/Kit/PGRKit.h"

static NSString *const kCardIdentifier = @"CreateMenu.ScrollView";
static char kCardKey, kCardGlassKey;

static void glassCard(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    UIView *card = root ? PGRFindByIdentifier(root, kCardIdentifier, &kCardKey) : nil;
    UIView *host = card.superview;
    if (!host) return;
    CGFloat radius = card.layer.cornerRadius;
    UIView *glass = PGGlassFor(host, &kCardGlassKey);
    if (!CGRectEqualToRect(glass.frame, card.frame)) glass.frame = card.frame;
    PGShapeGlass(glass, radius, NO);
    PGRThickenSheetGlass(glass, radius);
    if (PGIsVisibleColor(card.layer.backgroundColor)) card.backgroundColor = UIColor.clearColor;
}

static void glassSheet(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (root) PGRGlassSheetChrome(root);
}

// The rows are built after the first layout and Spotify paints its grey back on later passes, so the pass
// runs when the view appears and a beat after, as the queue's and the attribution sheet's do.
static void afterAppear(UIViewController *controller, void (*chrome)(UIViewController *)) {
    __weak UIViewController *weak = controller;
    chrome(controller);
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}

%hook _TtC29CreateMenu_CreateMenuPageImpl24CreateMenuViewController
- (void)viewDidLayoutSubviews {
    %orig;
    glassCard((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    glassCard((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    afterAppear((UIViewController *)self, glassCard);
}
%end

%hook _TtC30PlaylistCreation_SheetPageImpl35BICreatePlaylistSheetViewController
- (void)viewDidLayoutSubviews {
    %orig;
    glassSheet((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    glassSheet((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    afterAppear((UIViewController *)self, glassSheet);
}
%end

%ctor {
    if (!PGRedesignedUI()) return;
    %init;
    PGRequireClasses(@[@"_TtC29CreateMenu_CreateMenuPageImpl24CreateMenuViewController",
                       @"_TtC30PlaylistCreation_SheetPageImpl35BICreatePlaylistSheetViewController"]);
}
