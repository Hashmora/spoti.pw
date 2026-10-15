// The redesign of the pages Spotify draws under a plain UINavigationBar (SPNavigationBar) rather than under a header
// of its own: the glass the Playlist, Album and Artist pages have at the top, on the pages that had none.
//
//     PageBar.m       the bar: its blur taken off, the page's title on a glass capsule, the back button and the
//                     page's ⋯ pinned to the corners as glass circles (Kit/SGRActionRow.h)
//     Recents.x       the listening history (Recents_RecentsPageImpl): the bar, its chips on glass, and the list
//                     run under the bars instead of stopping short of them
//     YourUpdates.x   the left menu's Your Updates (YourUpdates_CommonImpl): the bar
//     ShowSearch.x    a podcast's "Find in this show" page (ShowPage_ShowSearchPageImpl): the bar, the field and Cancel on glass
//
// Every hook installs only while Redesigned UI is on and below iOS 26, where the bars are the system's.
// Threading: main thread only.
#import <UIKit/UIKit.h>

// A Swift class by module and name, under the mangled spelling or the dotted one the trees print; Nil when the
// app has neither.
Class SGRPageClass(NSString *module, NSString *name);

// Dresses the bar of the navigation controller `page` is in, while `page` is the one on screen: from its layout
// passes and as it appears. Cheap to call again.
void SGRDressBarPage(UIViewController *page);
// Gives the bar back the way Spotify made it, for the next page: as `page` goes.
void SGRUndressBarPage(UIViewController *page);

// Registers a page the redesign dresses: `wants` says whether the page on top of a navigation controller is one. While one is,
// Spotify's blur behind the bar is kept off from the moment the page is pushed, instead of from the first pass of the page
// that finds the bar, and again whenever Spotify brings it back (the app left and entered again).
typedef BOOL (^SGRBarPageTest)(UIViewController *top);
void SGRRegisterBarPages(SGRBarPageTest wants);
// Puts the blur of `navigation` where its top page wants it: drawn by nothing for a dressed page, Spotify's again for any other.
// Cheap to call again.
void SGRSyncBarBlur(UINavigationController *navigation);
