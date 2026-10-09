// The redesign's navbar: the glass tab bar (TabBar.x) over Spotify's own, composed from its own list
// (Navbar.x, NavbarLayout.m), which the redesign keeps apart from the native look's: an ordered list of
// entries, each a dictionary. An entry with a URI is a tab of the mod's own; one without names
// one of Spotify's, by the label under its icon. No list at all is Spotify's order, all shown.
#import <UIKit/UIKit.h>

#define PGRKeyNavbar @"pureglass.redesign.navbar"
// Icons only on the glass bar. Off unless set; applies as soon as the bar lays out again.
#define PGRKeyNavbarHideLabels @"pureglass.redesign.navbar.hideLabels"

// What the Navbar page of Mod Settings says, whichever tweak's page it is: spoti.pw's own is the page there is
// (SGRNavbarPage), and it writes under that tweak's prefix, so with it in the app these read its keys and
// fall back on this tweak's own (PGRKeyNavbar...) while it has none. See NavbarLayout.m.
BOOL PGRNavbarEnabled(void);
BOOL PGRNavbarLabelsHidden(void);

extern NSString *const PGRNavbarID;      // NSString, the entry's identity
extern NSString *const PGRNavbarTitle;   // NSString, the name in the settings list and under the icon
extern NSString *const PGRNavbarURI;     // NSString, the mod's own tabs only: what a tap opens
extern NSString *const PGRNavbarIcon;    // NSString, an SPTEncoreIcon class method such as "podcasts"
extern NSString *const PGRNavbarHidden;  // NSNumber
NSArray<NSDictionary *> *PGRNavbarLayout(void);
void PGRSetNavbarLayout(NSArray<NSDictionary *> *layout);
// Spotify's own tabs in Spotify's order, as Navbar.x last saw them on the bar.
NSArray<NSString *> *PGRNavbarStock(void);
void PGRSetNavbarStock(NSArray<NSString *> *stock);
// Hands the same list to the other tweak's Navbar page when it has one (NavbarLayout.m).
void PGRMirrorNavbarStock(NSArray<NSString *> *stock);
// What a tab of the mod's own opens: its URI as typed or pasted, share links made spotify: URIs, and
// the URIs of presets that never opened (spotify:collection:playlists, up to 0.20) moved to the ones
// that replaced them, so a tab saved back then works without being added again.
NSURL *PGRNavbarTabURL(NSString *uri);

// Navbar.x, called from the tab bar's layout passes in TabBar.x.
void PGRComposeTabBar(UIView *tabBar);
// Lays the bar out again after the Navbar page changes something, so it does not wait for a touch.
void PGRRefreshTabBar(void);
