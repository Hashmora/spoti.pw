// Glass for the redesign's control layer, and only for it: never behind rows, cards or text. Built on
// Core/SGGlass.m (the effect made through +effectWithStyle:). Under Reduce Transparency a shape is a
// solid SGRSolidGlassFill, on any OS; before iOS 26 without it, a dark thin material blur. Nothing
// touches a glass class on an OS without them. A shape is dark whatever the system appearance: glass
// takes the one it inherits, which outside the navigation stacks Spotify makes dark (the player) is the
// system's, light on a phone in light mode.
//
// Ownership: a shape belongs to the control it is made in (associated with it under the caller's key).
// Threading: main thread only.
#import <UIKit/UIKit.h>

// A glass circle inside someone else's round control, `side` across, behind everything the control
// draws (first in its subviews, re-asserted on every call, since glass takes what is above it in the
// tree into its backdrop however the depths are set) and kept at its middle by the autoresizing mask.
// Being the control's own
// subview it goes wherever the control goes: a frame worked out from outside goes stale when Spotify
// lays a row out after the unit that holds it (the player's header circles sat 24pt off until a tap
// laid the unit out again, trees/continuous/1.txt 2026-09-17). Takes no touches; made once per control
// under `key`, and made again when Reduce Transparency changes the kind of shape.
UIView *SGRGlassInside(UIView *control, const void *key, CGFloat side);

// The same, in a capsule `size` across rather than a circle: for the one control of an action row that
// leads (the playlist header's Play). `prominent` lays a white film inside the shape, so that control
// reads a step brighter than the circles beside it without leaving the same material.
UIView *SGRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent);

// Shows or hides a shape of the Kit's by its effect, never by an alpha on it or on a view above it
// (Redesigned/Player/PlayerMotion.x): UIKit draws the material wrongly or not at all under a fading alpha.
// The solid shape Reduce Transparency puts in its place has no effect and fades by its own alpha. Animates
// in the caller's animation.
void SGRShowGlass(UIView *shape, BOOL shown);
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
// at that list and leaves its rows alone. Also records the sheet in sgr_sheetChromeRoot (SGRRepaint.h), whose
// hook keeps the fill clear when Spotify paints it back.
UIView *SGRGlassSheetChrome(UIView *content);
// The top corner radius of every sheet the mod glasses: the screen's, as the Genius meanings sheet has it.
CGFloat SGRSheetCornerRadius(void);
// The body SGRGlassSheetChrome puts on a sheet's pane (heavier blur, dark tint, hairline rim), for a sheet
// the mod presents itself and that has no "sheet-view" to find (the Genius meanings sheet).
void SGRThickenSheetGlass(UIView *glass, CGFloat cornerRadius);
// A black layer over the body SGRThickenSheetGlass gives a pane, for menus whose white text the light body
// leaves too little contrast to read. Call it after SGRThickenSheetGlass.
void SGRDimSheetGlass(UIView *glass, CGFloat alpha);

// Whether `view` is chrome of the sheet rooted at `root` (sgr_sheetChromeRoot) rather than a row or card
// inside the sheet's own list.
BOOL SGRIsSheetChromeArea(UIView *view, UIView *root);

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
