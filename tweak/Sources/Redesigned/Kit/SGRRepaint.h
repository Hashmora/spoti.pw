// The areas the redesign stripped and SGRRepaint.x keeps transparent when Spotify repaints them, each
// set by the part of the redesign that owns it.
#import <UIKit/UIKit.h>

extern __weak UIView *sgr_nowPlayingRoot;   // Redesigned/NowPlayingBar/NowPlayingBar.x, the bar
// Every view in the bar Spotify painted as a card, learned from the album-color paint, which goes clear. The bar
// makes the set and picks its card from it: in a Jam Spotify also paints the Jam strip, or a view around the
// strip and the track.
extern NSHashTable<UIView *> *sgr_nowPlayingPainted;
extern __weak UIView *sgr_lyricsPageRoot;   // Redesigned/Lyrics/LyricsPage.x
// Redesigned/Playlist/PlaylistField.x, the playlist page. Only the base surface Spotify paints the page,
// its list and its rows with goes clear here: the artwork field is underneath, and the grays of a
// placeholder or a badge are what still has to read against it.
extern __weak UIView *sgr_playlistRoot;
// Redesigned/Album/AlbumField.x, the album page, kept clear the same way and for the same reason.
extern __weak UIView *sgr_albumRoot;
// Redesigned/Artist/ArtistField.x, the artist page, kept clear the same way and for the same reason.
extern __weak UIView *sgr_artistRoot;
// Kit/SGRGlass.h's SGRGlassSheetChrome: the "sheet-view" pane it glassed (the ⋯ context menu, the queue,
// and the now-playing bar's pop-art track info, one component under all three). Any opaque fill its chrome
// repaints outside the sheet's own list (SGRIsSheetChromeArea) is cleared here on every repaint: Spotify
// draws it back on its own later, and a view built after the first pass is never stripped otherwise.
extern __weak UIView *sgr_sheetChromeRoot;

// Search/SearchHeader.x, iOS < 26: the view of the search results header (Spotify's #1F1F1F backing, which the page
// puts back on its own passes) and the grey capsule inside its field. Both are kept clear while they are set.
extern __weak UIView *sgr_searchHeaderRoot;
extern __weak UIView *sgr_searchFieldFill;

// Playlist/PlaylistAddSearch.x, iOS < 26: the grey search bar at the bottom of the Add songs sheet's pages, kept clear
// while it is set (Spotify paints it again when the field is focused).
extern __weak UIView *sgr_addSongsSearchBar;

// Defined in Redesigned/Library/LibraryHeader.x, declared here because the repaint hook is lower than the
// part: a library filter chip's fill was just painted (selected, deselected, pressed), so its glass is brought
// in line with the paint -- shown over a clear fill, hidden under a selected colour -- without a layout pass.
void SGRLibraryChipPainted(UIView *chip);
