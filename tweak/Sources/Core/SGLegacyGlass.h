// The pre-iOS 26 stand-in for UIGlassEffect: a CABackdropLayer, blurred and saturated, displaced by a
// mesh so its edges refract the way real glass does. Geometry and filter values are ported from
// Telegram-iOS's GlassBackgroundComponent and MeshTransform (GPLv2); no Telegram code is kept verbatim.
//
// CABackdropLayer and CAMutableMeshTransform are private API Apple can remove at any point, so the
// whole thing sits behind SGLegacyGlassAvailable() and the "legacy glass" switch (SGKeyLegacyGlass),
// and every call fails soft to a plain blur. Callers go through SGUseLegacyGlass() (SGGlass.h), which
// combines both.
#import <UIKit/UIKit.h>

// NO on iOS 26+ (UIGlassEffect is used there) and wherever the private classes turn out not to exist.
// Cached after the first call.
BOOL SGLegacyGlassAvailable(void);

// One pane per call site, like UIVisualEffectView. It keeps its own backdrop layer and mesh sized to
// its bounds, so a pane resized by autoresizing or Auto Layout follows with no help from the caller.
@interface SGLegacyGlassView : UIView

// Where a caller puts its own content, like UIVisualEffectView.contentView: the backdrop and the mesh
// live behind it.
@property (nonatomic, strong, readonly) UIView *contentView;

// Corner radius of the glass. Ignored while `capsule` is set, which rounds to half the shorter side.
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) BOOL capsule;

// How far the backdrop is blurred, 2 by default: enough to soften an edge, and so little that a small
// control over text shows the text. A big pane (a sheet) sets more, or the page under it takes the eye.
@property (nonatomic) CGFloat blurRadius;

@end
