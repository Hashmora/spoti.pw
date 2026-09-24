// The pre-iOS 26 fallback for real glass: a CABackdropLayer, blurred and saturated, displaced by a
// mesh so its edges refract like UIGlassEffect's. Ported from Telegram-iOS's GlassBackgroundComponent
// and MeshTransform (GPLv2, submodules/TelegramUI/Components) — geometry and filter values only, no
// Telegram code retained verbatim. Gated behind the "legacy glass" switch (SGKeyLegacyGlass) and
// behind SGLegacyGlassAvailable(): both CABackdropLayer and CAMutableMeshTransform are private API
// that Apple can remove at any point, so every call here fails soft to a plain blur.
#import <UIKit/UIKit.h>

#define SGKeyLegacyGlass @"spotifyglass.legacyglass"

// NO on iOS 26+ (UIGlassEffect is used instead), and NO wherever CABackdropLayer or
// CAMutableMeshTransform turn out not to exist. Cheap after the first call; cache the result if
// calling it every layout pass.
BOOL SGLegacyGlassAvailable(void);

// One pane per call site, like UIVisualEffectView. `clear` matches Telegram's .clear style (lighter
// blur, no saturation boost) for panes over already-busy content (album art, a fully-drawn player);
// leave it NO for the flat chrome under the navigation bar and the player's round controls.
@interface SGLegacyGlassView : UIView

// Where a caller puts its own content, exactly like UIVisualEffectView.contentView: the backdrop
// layer and the mesh live behind it, unaffected by what's added here.
@property (nonatomic, strong, readonly) UIView *contentView;

- (void)updateWithSize:(CGSize)size cornerRadius:(CGFloat)cornerRadius capsule:(BOOL)capsule clear:(BOOL)clear;

@end
