// What drives the native look's navbar: Spotify's tab bar composed on its layout passes (Navbar.x), and
// holding Home opens Mod Settings.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView of
//   ElementContentView<TabBarItemElement>, each with an SPTEncoreIconView and an SPTEncoreLabel.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Settings/SGPage.h"

@interface SGHomeHold : UILongPressGestureRecognizer
@end

@implementation SGHomeHold
+ (void)held:(SGHomeHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) SGOpenModSettings(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so Home is not tapped too.
static void holdHome(UIView *stockBar) {
    UIView *home = SGRowIn(stockBar).arrangedSubviews.firstObject;
    if (!home) return;
    for (UIGestureRecognizer *recognizer in home.gestureRecognizers) {
        if ([recognizer isKindOfClass:SGHomeHold.class]) return;
    }
    [home addGestureRecognizer:[[SGHomeHold alloc] initWithTarget:SGHomeHold.class action:@selector(held:)]];
}

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

static char kTabBarGlassKey;

// Glass under the whole bar, the way the redesign's system UITabBar gets it for free from UIKit on
// iOS 26+ (Redesigned/Navbar/TabBar.x): below that, with the legacy switch on, the same
// backdrop-and-mesh pane Player.x puts behind the round header buttons goes behind the bar instead.
// Spotify paints the bar as flat chrome, so that fill is cleared first or the pane would never show.
static void glassBehindTabBar(UIView *tabBar) {
    if (@available(iOS 26.0, *)) return;
    if (!SGFlag(SGKeyLegacyGlass, NO) || !SGLegacyGlassAvailable()) return;
    tabBar.layer.backgroundColor = NULL;
    UIView *glass = SGGlassFor(tabBar, &kTabBarGlassKey);
    // Dark whatever the system is set to, as the player's header panes are (Player.x): light glass
    // under the bar's white icon otherwise, on a phone in light mode.
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    glass.frame = tabBar.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    SGShapeGlass(glass, 0, NO);
}

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    %orig;
    SGComposeTabBar((UIView *)self);
    holdHome((UIView *)self);
    glassBehindTabBar((UIView *)self);
    SGLogTabBarRow((UIView *)self);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive.
static void itemDidLayOut(UIView *item) {
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    SGComposeTabBar(bar);
    holdHome(bar);
    SGLogTabBarRow(bar);
}

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
    ]);
}
