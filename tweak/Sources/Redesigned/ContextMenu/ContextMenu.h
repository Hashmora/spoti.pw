// The redesign's ⋯ opens the system menu instead of Spotify's sheet, the way the Music app's does: the player's
// and, on iOS 26, the ⋯ every redesigned entity page pins to its corner (playlist, album, artist and the pages
// that share their templates). Below iOS 26 only the player's does; a page's ⋯ opens Spotify's own sheet, which
// gets the glass pane and corners of SGRGlassSheetChrome. Always on in the redesign; no setting.
//
//     ContextMenu.x   the takeover: Spotify's sheet presented unseen, its rows read into a UIMenu shown from
//                     the ⋯, a pick fired on the sheet, and the sheet itself as the fallback
//
// Spotify's rows come from Swift item factories with nothing to read them from but the cells they fill, so
// the sheet is still Spotify's and still made, unseen.
//
// The player's ⋯ is a pull-down button of the mod's: a button over Spotify's ⋯ takes its touches and opens
// the menu on touch down, as UIKit opens any button's menu, so it waits on nothing of Spotify's. Share, Add to
// playlist and Add to queue (Spotify's items 9, 19 and 11, or found by title) are a row of three at its top, as
// the last sheet of this kind had them, then come the player's own items, then More, which holds the rest of
// Spotify's rows: the last complete set stored, at once, or the system's loading row the first time, put right
// in place as the live rows come. Once the menu is up, Spotify's ⋯ action is run from code; its sheet is
// presented in a window of the mod's under the app's (the menu, a presentation of UIKit's from the player,
// leaves no room for another there), read, and used to run a pick. A pick made before the live rows are in
// waits up to 4 s for them, else the sheet is shown.
//
// A page's ⋯ is the other way round: its tap opens Spotify's sheet, presented without animation in a container
// at alpha 0 from its first frame, and the menu opens over it from an invisible anchor button inside the ⋯, its
// rows a deferred element that waits for them.
//
// A pick closes the menu and then selects that row on the sheet, so what it does stays Spotify's; a pick that
// leaves the sheet up (a row opening a page of its own) shows the sheet. Rows the mod puts in the sheet's
// header or footer (Sort and Mix on a playlist, Edit info for a local file) are read the same way and fired the
// same way. Closing the menu without a pick dismisses the sheet.
//
// A page's anchor takes touches only while its menu is up, so every other tap reaches the ⋯ under it, and the
// menu is opened with -[UIControl performPrimaryAction] (iOS 17.4), else UIContextMenuInteraction's private
// _presentMenuAtLocation:, each checked with respondsToSelector:. When neither is there, or the menu does not
// come up, Spotify's sheet shows at once instead, with nothing waited out.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Items of the mod's own for the menu `button` opens, built afresh every time it opens.
typedef NSArray<UIMenuElement *> *(^SGRMenuItems)(void);
// What the sheet the ⋯ opens now is for ("track", "episode"...). The menu remembers which quick items the last
// sheet of each kind had, so the quick row is right before this sheet has its rows.
typedef NSString *(^SGRMenuKind)(void);

// Makes `button`, the player's ⋯ (a UIControl), open the system menu itself: the quick row, `items`, then More.
// `kind` may be nil. Called on every layout of the ⋯'s row: it keeps the mod's button on top and over the whole
// ⋯, and replaces `items` and `kind`. The pinned ⋯ of the entity pages needs no call: the Kit records its taps
// (SGRPinnedMoreRecentButton).
void SGRSystemMenuWatch(UIView *button, SGRMenuItems items, SGRMenuKind kind);

// The mod's button over `button`, which takes the ⋯'s touches once SGRSystemMenuWatch has been called; nil before.
UIControl *SGRSystemMenuFront(UIView *button);

// The glass the system menu has below iOS 26, on `host` under `key`: SGRMenuGlass (ContextMenuGlass.x) is what the
// menu's platter gets (SGRMenuDim) and what the sliders' panel under the ⋯ takes for its background with a dim
// of its own. Nil while `host` has no size.
static const CGFloat SGRMenuDim = 0.42;
UIView *SGRMenuGlass(UIView *host, const void *key, CGFloat dim);

// Below iOS 26, the player's ⋯ menu opens the way iOS 26's does (MenuMorph.m): the button flies down into the
// menu's middle while the menu grows out of it. Prepare is told the button before the menu is asked for, Open is
// run on the first layout with a size of a menu's list (only the first after a Prepare morphs), Shown as the menu
// is shown (it morphs then if Open did not), Close as it ends.
void SGRMenuMorphPrepare(UIView *source);
void SGRMenuMorphOpen(UIView *list);
// Holds the menu view of `list` unseen from its first moment in a window until the morph starts (MenuMorph.m).
void SGRMenuMorphHold(UIView *list);
void SGRMenuMorphShown(void);
void SGRMenuMorphClose(UIView *source);
