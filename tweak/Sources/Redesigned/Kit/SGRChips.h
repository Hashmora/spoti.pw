// Encore's filter chips (a ChipView over a PillView) on glass, below iOS 26: for the pages whose chips are not the
// library's FilterChipView -- the genres over Liked Songs (Playlist/PlaylistChips.x) and the Podcasts / Music chips
// of Recents (Pages/Recents.x). The chips of the Add to playlist sheet are a different class, Home_PillUIKit's
// PillView, and are dressed by SGRSheetPills.x on its own.
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

// The chips of a sheet (the Add to playlist sheet's, Home_PillUIKit.PillView), dressed by SGRSheetPills.x. For
// SGRRepaint.x: whether `view` is such a pill, whether a paint is the flat grey of an unselected one, and the pill's
// glass is brought in line with a paint that has just landed on it.
BOOL SGRSheetPillsLive(void);   // a pill has been dressed; false until then, so a hook need not look
BOOL SGRIsSheetPill(UIView *view);
BOOL SGRIsPillGrey(CGColorRef color);
void SGRSheetPillPainted(UIView *pill);
