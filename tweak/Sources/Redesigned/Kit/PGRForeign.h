// Another tweak drawing on the same pages: spoti.pw's Redesigned UI, whose views are this tweak's own
// classes under the prefix SGR (SGRHeaderInfo beside PGRHeaderInfo, SGRMirrorButton beside PGRMirrorButton,
// SGRArtworkField beside PGRArtworkField...), plus plain UIVisualEffectView panes laid over the same boxes as
// this tweak's glass. With Glass UI on, this tweak's views are the only ones drawn, and this file is the
// whole of how that is kept:
//
//   1. A view of the other tweak that this one has a class of its own for is concealed when it comes into a
//      window (the hook in PGRForeign.x). Not on the player screen, where this tweak draws nothing and the
//      other one's extras (its lyrics button, its shadow plates) are all there is.
//   2. A UIVisualEffectView laid over one of this tweak's glass panes is concealed (PGREvictTwinPanes, and the
//      hook for one that arrives after the pane).
//   3. This tweak's header info cannot be concealed by the other tweak's own sweep. Both tweaks add their
//      info to the same block of Spotify's header and then conceal every other subview of it, so each hid the
//      other's: neither drew the shuffle, Play and download row (PGR_STEADY_VIEW).
//
// "Concealed" is what Playlist/PlaylistHeader.x's conceal() does: the layer hidden and masked by an empty
// layer, so a later -setHidden:NO of the other tweak's still draws nothing, and no touches.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Whether `view` is a view of the other tweak that this tweak draws its own version of: a class named SGR...
// that comes from another image than this one's, with a PGR... class of the same name. The classes the other
// tweak makes at run time to watch Spotify's own views (SGRImageObserved_UIImageView and the like) are
// Spotify's views and are never taken.
BOOL PGRIsForeignOverlay(UIView *view);

// Takes `view` out of sight and out of reach for good, whatever its owner does to it afterwards.
void PGRConcealForeign(UIView *view);

// Conceals the UIVisualEffectViews beside `pane` (in its superview) that this tweak did not make and that
// cover it: the other tweak's own pane over the same box. Safe to call on every layout pass; `pane` has its
// final frame by then.
void PGREvictTwinPanes(UIView *pane);

// Whether the code that is calling (`returnAddress` is __builtin_return_address(0) of the callee) belongs to
// the other tweak's image. NO when there is no such tweak.
BOOL PGRCalledFromForeign(void *returnAddress);

// A layer that does not take the other tweak's hide or mask. Writes from anywhere else (UIKit, Spotify, this
// tweak) go through.
@interface PGRSteadyLayer : CALayer
@end

// Put inside the @implementation of a view the other tweak sweeps with its own conceal(): the layer, the
// touches, the accessibility and -setHidden: of the view are then out of that sweep's reach.
#define PGR_STEADY_VIEW \
+ (Class)layerClass { return PGRSteadyLayer.class; } \
- (void)setHidden:(BOOL)hidden { \
    if (hidden && PGRCalledFromForeign(__builtin_return_address(0))) return; \
    [super setHidden:hidden]; \
} \
- (void)setUserInteractionEnabled:(BOOL)enabled { \
    if (!enabled && PGRCalledFromForeign(__builtin_return_address(0))) return; \
    [super setUserInteractionEnabled:enabled]; \
} \
- (void)setAccessibilityElementsHidden:(BOOL)hidden { \
    if (hidden && PGRCalledFromForeign(__builtin_return_address(0))) return; \
    [super setAccessibilityElementsHidden:hidden]; \
}
