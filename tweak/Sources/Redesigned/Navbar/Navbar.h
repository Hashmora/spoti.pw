// The redesign's navbar: the glass tab bar (TabBar.x) over Spotify's own, composed from its own list
// (Navbar.x, NavbarLayout.m), which the redesign keeps apart from the native look's: an ordered list of
// entries, each a dictionary. An entry with a URI is a tab of the mod's own; one without names
// one of Spotify's, by the label under its icon. No list at all is Spotify's order, all shown.
#import <UIKit/UIKit.h>

#define SGRKeyNavbar @"spotifyglass.redesign.navbar"
// Compact bar: scrolling down folds the glass bar and the now playing card into one row (selected tab,
// player, search), scrolling up or reaching the top unfolds them. Off unless set (CompactBar.m).
#define SGRKeyNavbarCompact @"spotifyglass.redesign.navbar.compact"
// Icons only on the glass bar. Off unless set; applies as soon as the bar lays out again.
#define SGRKeyNavbarHideLabels @"spotifyglass.redesign.navbar.hideLabels"

extern NSString *const SGRNavbarID;      // NSString, the entry's identity
extern NSString *const SGRNavbarTitle;   // NSString, the name in the settings list and under the icon
extern NSString *const SGRNavbarURI;     // NSString, the mod's own tabs only: what a tap opens
extern NSString *const SGRNavbarIcon;    // NSString, an SPTEncoreIcon class method such as "podcasts"
extern NSString *const SGRNavbarHidden;  // NSNumber
NSArray<NSDictionary *> *SGRNavbarLayout(void);
void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout);
// Spotify's own tabs in Spotify's order, as Navbar.x last saw them on the bar.
NSArray<NSString *> *SGRNavbarStock(void);
void SGRSetNavbarStock(NSArray<NSString *> *stock);
// What a tab of the mod's own opens: its URI as typed or pasted, share links made spotify: URIs, and
// the URIs of presets that never opened (spotify:collection:playlists, up to 0.20) moved to the ones
// that replaced them, so a tab saved back then works without being added again.
NSURL *SGRNavbarTabURL(NSString *uri);

// Navbar.x, called from the tab bar's layout passes in TabBar.x.
void SGRComposeTabBar(UIView *tabBar);
// Lays the bar out again after the Navbar page changes something, so it does not wait for a touch.
void SGRRefreshTabBar(void);

UIViewController *SGRNavbarSettingsPage(void);   // the tab editor, in Mod Settings
UIViewController *SGRNavbarEditorPage(void);     // the tab editor alone, for the welcome tour

// CompactBar.m. The row's state is the bar's own: it starts unfolded and goes back there for a tab change,
// the player opening and the switch being turned off.
void SGRCompactBarSynced(UIView *stockBar);              // end of every pass of TabBar.x's sync
void SGRCompactBarSetCollapsed(BOOL collapsed, BOOL animated);
void SGRCompactBarNowPlayingChanged(void);               // NowPlayingBar.x, after the card is styled

// TabBar.x, for CompactBar.m. The capsule's host (nil before the bar exists) and the platter's frame in the
// stock bar's coordinates; the container Spotify's tab pages live in; the glyph of the tab that is open and
// of the tab the row's right circle goes to (Search, or Home while Search is open); a tap on that circle.
UIView *SGRTabBarStock(void);
UIView *SGRTabBarCapsule(CGRect *platter);
UIView *SGRTabBarContainerView(void);
UIImage *SGRTabBarCurrentGlyph(void);
UIImage *SGRTabBarSideGlyph(void);
void SGRTabBarSideTap(void);
// Spotify's own tap handling replayed on a view: through its tap recognizers only, or, for a tab or a
// button, through whatever answers.
BOOL SGRFireTapRecognizers(UIView *view);
void SGRForwardTap(UIView *item);
