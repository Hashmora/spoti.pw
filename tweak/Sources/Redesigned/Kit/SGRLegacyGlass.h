// What this fork adds to the redesign's glass kit, for the redesign running below iOS 26 (SGBelowIOS26 in
// Core/SGLegacyGlass.h). It sits beside SGRGlass.h and SGRActionRow.h rather than in them, so those stay as
// the author wrote them and a merge from upstream has nothing of the fork's to fight with. Every caller
// hangs its call on SGBelowIOS26(); on iOS 26 none of this runs.
#import <UIKit/UIKit.h>
#import "SGRActionRow.h"

@class SGModRow;

// Glass behind a flat box Spotify draws as a grey rounded rect (a search field, a sort button): the box is
// cleared and made a capsule, and a glass capsule goes inside it. Safe to call on every pass.
UIView *SGRGlassFlatBox(UIView *box, const void *key);

// The faint white film over a floating bar's glass (the tab bar's platter, the now playing card), without
// which the bar disappears into Spotify's near-black chrome. Made once under `key`, kept just above `glass`
// and on its frame, with corners of `radius`.
UIView *SGRGlassFilm(UIView *host, const void *key, UIView *glass, CGFloat radius);

// The chrome of a bottom sheet Spotify draws around an opaque "sheet-view" pane: the ⋯ context menu, the
// queue, and the pop-art track info under the now playing bar. A glass pane goes behind the pane's own
// paint and the plain wrapper views between it and the sheet's first scrolling list lose their fill. Stops
// at that list and leaves its rows alone. Also records the sheet in sgr_sheetChromeRoot, whose hook
// (SGRLegacyRepaint.x) keeps the fill clear when Spotify paints it back.
UIView *SGRGlassSheetChrome(UIView *content);
extern __weak UIView *sgr_sheetChromeRoot;

// The body SGRGlassSheetChrome puts on a sheet's pane (heavier blur, dark tint, hairline rim), for a sheet
// the mod presents itself and that has no "sheet-view" to find (the Genius meanings sheet).
void SGRThickenSheetGlass(UIView *glass, CGFloat cornerRadius);

// The opaque dark grey (up to 0.20 bright, grey, alpha >= 0.95) Spotify paints a sheet's rows and wrappers
// with: #1F1F1F, which SGIsBaseSurface (the page black, up to 0.10) does not take for paint.
BOOL SGRIsSheetSurface(CGColorRef color);

// Clears the bands a row of the sheet's list paints (the cell, the stacks in it nearly as wide as the sheet
// `root`). For a cell that comes into the sheet after the chrome was stripped: scrolled in, reused, or
// dragged. Safe to call on every layout pass.
void SGRClearSheetCellPaint(UIView *cell, UIView *root);

// Whether `view` is a card the sheet draws on purpose (a SwiftUI shape, or a narrower rounded fill) rather than
// the grey of a wrapper: SGRGlassSheetChrome and the repaint hook leave these alone.
BOOL SGRIsSheetCard(UIView *view);

// The translucent white a SwiftUI card of a sheet (the device picker's, #292929 opaque) is painted instead,
// and whether `view` is such a card.
CGColorRef SGRSheetCardFill(void);
BOOL SGRIsSwiftUICard(UIView *view);

// SGRObserveLayout (SGRRestyle.h) for the views it cannot subclass: one of Spotify's Swift classes (a library
// filter chip) gets the override on its class instead.
BOOL SGRLegacyObserveLayout(UIView *view, void (^laidOut)(UIView *view));
// Whether `view` is chrome of the sheet rooted at `root` (sgr_sheetChromeRoot) rather than a row or card
// inside the sheet's own list.
BOOL SGRIsSheetChromeArea(UIView *view, UIView *root);

// The mirror of SGRPinnedMore (SGRActionRow.h) at the leading edge: one glass circle, the same size and inset,
// in place of Spotify's own back button, which is hidden. Resizing and glassing Spotify's box in place fought
// the header's collapse animation on every scroll, so every header pins this independent button instead.
//
// `searchRoot` is where Spotify's back button (Components.Header.UI.BackButton) is looked for; until it is
// found the pinned button stays hidden. Kept on `page`, and cheap to call on every pass.
SGRMirrorButton *SGRPinnedBack(UIView *page, UIView *searchRoot);

// The "Legacy Liquid Glass" row of the redesign's Appearance card: a switch where the device has the private
// APIs it leans on (SGLegacyGlassAvailable()), a row that says so where it has not.
SGModRow *SGRLegacyGlassRow(void);
