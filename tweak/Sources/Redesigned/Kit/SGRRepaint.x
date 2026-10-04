// Keeps the areas the redesign stripped transparent when Spotify repaints them, and learns which view
// is the now playing bar's card from the album-colour paint.
#import "Core/SGCore.h"
#import "SGRRepaint.h"
#import "SGRGlass.h"
#import <objc/runtime.h>

__weak UIView *sgr_nowPlayingRoot = nil;
__weak UIView *sgr_nowPlayingCard = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;
__weak UIView *sgr_sheetChromeRoot = nil;

// The flat, translucent white Spotify tints an unselected filter chip with (bg=#FFFFFF@0.10, trees/continuous/26.txt
// 2026-09-26). A selected chip is painted a solid colour of its own, which is never this.
static BOOL isNeutralTint(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID()) return NO;
    CGFloat alpha = CGColorGetAlpha(color);
    if (alpha < 0.01 || alpha > 0.3) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    for (size_t i = 0; i + 1 < n; i++) if (c[i] < 0.9) return NO;
    return n >= 2;
}

// The fill of a library filter chip: the plain view FilterChipView lays under its label. Spotify paints
// it again on its own passes (a chip pressed, selected or let go, a cell coming back from reuse), none
// of which lays the library page out, so clearing it once from the page's pass left the grey back under
// the glass every time. Told apart by the class of its parent, not by a root: the root library and a
// folder can both be alive, and each has chips.
static char kChipFillKey;

void SGRMarkChipFill(UIView *fill) {
    if (fill) objc_setAssociatedObject(fill, &kChipFillKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL isChipFill(UIView *view) {
    // Home's pills: marked by HomePills.m, the pill itself or the plain view it lays under its label.
    if (objc_getAssociatedObject(view, &kChipFillKey)) return YES;
    if (view.superview == nil || ![view isMemberOfClass:UIView.class]) return NO;
    return [NSStringFromClass(view.superview.class) isEqualToString:@"EncoreConsumerMobile_BaseKit.FilterChipView"];
}

// The opaque backing Spotify paints the library's pinned header with (#121212, black under the AMOLED hook,
// trees/continuous/1.txt 2026-10-02). Library/LibraryHeader.x puts a black plate behind the title row alone
// so the filter chips can be glass over the list; this keeps Spotify's own paint from covering them again
// on its passes. Size first, name second: this runs for every colour any layer is given.
static BOOL isLibraryHeader(UIView *view) {
    CGSize size = view.bounds.size;
    if (size.width < 300 || size.height < 100 || size.height > 260) return NO;
    return [NSStringFromClass(view.class) hasSuffix:@"YourLibraryHeaderView"];
}

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (color && CGColorGetAlpha(color) > 0.5) {
        UIView *header = (UIView *)self.delegate;
        if ([header isKindOfClass:UIView.class] && header.layer == self && isLibraryHeader(header)) color = NULL;
    }
    if (isNeutralTint(color)) {
        UIView *fill = (UIView *)self.delegate;
        if ([fill isKindOfClass:UIView.class] && fill.layer == self && isChipFill(fill)) color = NULL;
    }
    if (color && (sgr_nowPlayingRoot || sgr_lyricsPageRoot || sgr_playlistRoot || sgr_albumRoot || sgr_artistRoot || sgr_sheetChromeRoot)) {
        UIView *view = (UIView *)self.delegate;
        if ([view isKindOfClass:UIView.class] && view.layer == self && !SGKeepsColor(view)) {
            if (SGIsInside(view, sgr_nowPlayingRoot)) {
                if (SGLooksLikeCard(view, color) && sgr_nowPlayingCard != view) {
                    sgr_nowPlayingCard = view;
                    UIView *bar = sgr_nowPlayingRoot;
                    dispatch_async(dispatch_get_main_queue(), ^{ [bar.superview setNeedsLayout]; });
                }
                color = NULL;
            } else if (SGIsInside(view, sgr_lyricsPageRoot)) {
                color = NULL;
            } else if (SGIsBaseSurface(color) && (SGIsInside(view, sgr_playlistRoot) || SGIsInside(view, sgr_albumRoot) || SGIsInside(view, sgr_artistRoot))) {
                color = NULL;
            } else if (SGIsVisibleColor(color) && SGRIsSheetChromeArea(view, sgr_sheetChromeRoot)) {
                color = NULL;
            } else if (SGRIsSheetSurface(color) && SGIsInside(view, sgr_sheetChromeRoot)
                       && sgr_sheetChromeRoot.bounds.size.width > 1
                       && view.bounds.size.width >= sgr_sheetChromeRoot.bounds.size.width * 0.75) {
                // A band in the sheet's own list (the queue's QueueCell and TrackRowQueue.Cell, #1F1F1F).
                color = NULL;
            }
        }
    }
    %orig(color);
}
%end

// A row coming into the sheet after its chrome was stripped (scrolled in, reused, picked up to be dragged)
// carries its grey with it, and is painted before it is inside the sheet for the hook above to hear of it,
// so it is cleared from its own layout pass, like SGRClearCellPaint does for the pages.
%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    UIView *root = sgr_sheetChromeRoot;
    if (root && SGIsInside((UIView *)self, root)) SGRClearSheetCellPaint((UIView *)self, root);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
