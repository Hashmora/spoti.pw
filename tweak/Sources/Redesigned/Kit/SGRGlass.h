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

// The chrome of a bottom sheet Spotify draws around an opaque "sheet-view" pane -- the ⋯ context menu's
// and the queue's alike, both this identifier (trees/continuous/24.txt, 26.txt 2026-09-26), and the same
// pane under the now-playing bar's pop-art track info (Shared/Player -- one component, three callers). A
// glass pane goes behind the pane's own paint, and the one or two plain views Spotify wraps around its own
// content between the pane and the sheet's first scrolling list are stripped of their background by hand:
// they are the same #1F1F1F card grey SGIsBaseSurface deliberately leaves alone everywhere else
// (SGRRepaint.x, where it is a placeholder or a real card), but here it is the sheet's own outer chrome,
// not a card inside it, and left standing it covered the glass whole bar a sliver at the very top. Stops
// at the first scroll view or table it meets and leaves that alone, rows and all.
//
// One strip on the pass that finds the sheet is not enough: Spotify repaints this same grey back in
// underneath on its own later passes (device 2026-09-26, Queue and the pop-art sheet both), the same way
// it repaints the playlist/album/artist fields SGRRepaint.x already guards. So this also records the
// sheet under sgr_sheetChromeRoot (SGRRepaint.h), whose continuous hook clears the grey every time Spotify
// repaints it, not just on the first pass.
UIView *SGRGlassSheetChrome(UIView *content);

// Whether `color` is Spotify's own #1F1F1F sheet-chrome grey (SGRGlassSheetChrome's fill, one tick above
// SGIsBaseSurface's), exposed so SGRRepaint.x's continuous hook can recognise and clear it wherever it
// gets repainted inside sgr_sheetChromeRoot.
BOOL SGRIsSheetChromeFill(CGColorRef color);
