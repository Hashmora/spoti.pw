// Encore's filter chips (a ChipView over a PillView) on glass, below iOS 26: for the pages whose chips are not the
// library's FilterChipView -- the genres over Liked Songs (Playlist/PlaylistChips.x) and the Podcasts / Music chips
// of Recents (Pages/Recents.x).
//
// An unselected chip's flat fill (#FFFFFF@0.10) goes and a glass capsule stands behind it, as the library's chips
// have theirs (Library/LibraryHeader.x); a selected chip keeps the solid colour it is painted, which is never the
// translucent white. Spotify paints the fill again as a chip is selected or let go, with no layout, so
// SGRRepaint.x keeps the tint off a pill of a chip dressed here and tells the chip.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Dresses every chip under `root` and watches each for its own layout, so a row laid out again at new widths (a
// chip picked) sizes the glass again. Cheap to call on every pass.
void SGRGlassChipsIn(UIView *root);

// Whether `view` is the pill of a chip dressed by SGRGlassChipsIn, and the chip's glass is brought in line with a
// paint that has just landed on it. For SGRRepaint.x.
BOOL SGRIsDressedChipPill(UIView *view);
void SGRDressedChipPainted(UIView *chip);
