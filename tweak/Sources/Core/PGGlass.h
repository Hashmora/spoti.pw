// Glass panes: one pane per host, kept behind the host's own content. The pane is real UIGlassEffect on
// iOS 26 and up. Below that it is an PGLegacyGlassView (an approximation built on private backdrop-layer
// API) when the device has that API, and a plain dark chrome blur otherwise.
#import <UIKit/UIKit.h>
#import "PGLegacyGlass.h"

// Whether panes are PGLegacyGlassViews right now. The one place this is decided: callers ask it instead of
// re-deriving the answer from @available and PGLegacyGlassAvailable().
BOOL PGUseLegacyGlass(void);

// UIGlassEffect, which is only made by +effectWithStyle:, or a dark chrome blur as the fallback.
UIVisualEffect *PGGlassEffect(void);
// A UIVisualEffectView or an PGLegacyGlassView. Callers set its frame and overrideUserInterfaceStyle and
// pass it to PGShapeGlass, so they need not tell the two apart.
UIView *PGGlassFor(UIView *host, const void *key);
// Several panes on one host, addressed by index; panes past `count` are hidden by PGHideGlassFrom.
UIView *PGGlassAt(UIView *host, NSUInteger index);
void PGHideGlassFrom(UIView *host, NSUInteger count);
// Glass takes its shape from cornerConfiguration on iOS 26, from PGLegacyGlassView's own corner radius
// below that, and from layer.cornerRadius on a plain blur.
void PGShapeGlass(UIView *glass, CGFloat radius, BOOL capsule);

// The areas each look keeps transparent are its own: Native/Appearance/Repaint.h and
// Redesigned/Kit/PGRRepaint.h.
