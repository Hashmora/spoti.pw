// Walking and reading Spotify's view trees.
#import <UIKit/UIKit.h>

void PGForEachView(UIView *view, void (^fn)(UIView *));
// The view `make` builds, made once and kept on `host` under `key`. Not added to the hierarchy.
UIView *PGLazyChild(UIView *host, const void *key, UIView *(^make)(void));
CGRect PGFrameIn(UIView *view, UIView *target);
// Whether `view` sits under `root`, stopping at a visual effect view on the way up.
BOOL PGIsInside(UIView *view, UIView *root);
// The first wide stack view under `host` with at least two arranged children: a player row, or
// the row of items in the tab bar.
UIStackView *PGRowIn(UIView *host);
// Whether any view under `root` has `marker` in its class name.
BOOL PGHasClass(UIView *root, NSString *marker);

// Artwork, glyphs, text and thin lines (progress bar) keep their colour, everything else goes clear.
BOOL PGKeepsColor(UIView *view);
void PGStripBackgrounds(UIView *view);
BOOL PGIsVisibleColor(CGColorRef color);
BOOL PGIsLightColor(CGColorRef color);
// Spotify's base surface: the neutral #121212 it paints its pages with, or the black AMOLED turns
// that into.
BOOL PGIsBaseSurface(CGColorRef color);
// A painted, card-sized view: the now playing bar's card, for one.
BOOL PGLooksLikeCard(UIView *view, CGColorRef color);
