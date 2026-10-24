// Below iOS 26, how iOS 26's glass moves between shapes, for the redesign's own glass (the system's does it itself from
// 26 on, and every call here does nothing there, under Reduce Motion, or without the legacy glass):
//
//   the morph    a control that gives way to another flows into it: a glass shape of the old one's place and corners
//                springs to the new one's, and the new one's own drawing comes in under it as the shape fades
//                (the Photos app's Select, which flows into ⋯ and ✕, ScreenRecording 2026-10-24, 2 s: about 0.2 s)
//
// It is drawn on views of the mod's own laid over the window, and the view that is arriving is only faded in by an
// animation added to its layer, whose model values stay as they were: nothing of Spotify's or UIKit's is hidden or
// moved, so a missed call or an early end leaves the screen as it would have been.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// The glass the morph's shape wears: a pane made inside `host`, which is clipped to the moving shape and
// sized to it by autoresizing. The caller's, so the shape matches what it stands for (a control's capsule, a menu's pane).
typedef UIView *(^SGRGlassMaker)(UIView *host);

// Notes the place of `view`, a glass control that is about to go (hidden or removed), for a morph into what replaces
// it. Call it before it goes, while it is still laid out on screen. Only the latest is kept.
void SGRGlassNoteLeaving(UIView *view);

// Flows the control noted by SGRGlassNoteLeaving in the last moment into `to`, which has just been shown: `to` is laid
// out first, so the shape ends where it ends. Nothing when no control was noted lately or `to` is not on screen.
void SGRGlassMorphFromLeaving(UIView *to, SGRGlassMaker glass);

// `bar` coming in as iOS 26's toolbars do when they take another's place: each of its controls grows in from a
// little smaller, blurred into view by its opacity, one a moment after the other.
void SGRGlassBarAppear(UIView *bar);
