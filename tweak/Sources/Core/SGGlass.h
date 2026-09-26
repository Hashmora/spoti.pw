// Glass panes: one pane per host, kept behind the host's own content. On iOS 26 and up the pane is
// real UIGlassEffect, drawn by the system; below that, with the person's "Legacy Liquid Glass" switch
// on and their device able to do it (SGLegacyGlassAvailable(), SGLegacyGlass.h), it is an
// SGLegacyGlassView instead, an approximation of the same look built on the private backdrop-layer
// technique iOS itself used for Liquid Glass before it was public API. Anywhere else, or with the
// switch off, it is a plain dark chrome blur, exactly as spoti.pw always drew it.
#import <UIKit/UIKit.h>

// Whether the Legacy Glass approximation should be used right now: below iOS 26 (UIGlassEffect
// covers 26 and up on its own), with the person's switch on, and with SGLegacyGlassAvailable()
// finding the private API it leans on. The one place this is decided -- Redesigned/Kit/SGRGlass.m
// calls this instead of re-deriving the same answer from the flag and @available itself.
BOOL SGUseLegacyGlass(void);

// UIGlassEffect made the only way that resolves its material, or a dark chrome blur as the fallback.
UIVisualEffect *SGGlassEffect(void);
// A UIVisualEffectView, or an SGLegacyGlassView standing in for one. Callers only ever set its frame
// and overrideUserInterfaceStyle and hand it to SGShapeGlass, so they need not tell the two apart.
UIView *SGGlassFor(UIView *host, const void *key);
// Several panes on one host, addressed by index; panes past `count` are hidden by SGHideGlassFrom.
UIView *SGGlassAt(UIView *host, NSUInteger index);
void SGHideGlassFrom(UIView *host, NSUInteger count);
// Glass takes its shape from cornerConfiguration on iOS 26, from SGLegacyGlassView's own mesh update
// below that, or from layer.cornerRadius as the last-resort fallback.
void SGShapeGlass(UIView *glass, CGFloat radius, BOOL capsule);

// The areas each look keeps transparent are its own: Native/Appearance/Repaint.h and
// Redesigned/Kit/SGRRepaint.h.
