#import "Core/SGCore.h"
#import "SGRGlass.h"
#import "SGRTokens.h"
#import "SGRRestyle.h"
#import "SGRRepaint.h"

// The redesign runs below iOS 26 only (SGRedesignAvailable()), so there is no system glass to use: a shape
// is the legacy approximation when it is on, a thin material blur when it is not, and a solid fill under
// Reduce Transparency.
typedef NS_ENUM(NSInteger, SGRGlassMode) {
    SGRGlassModeLegacy,
    SGRGlassModeBlur,
    SGRGlassModeSolid,
};

static SGRGlassMode glassMode(void) {
    if (SGRReduceTransparency()) return SGRGlassModeSolid;
    if (SGUseLegacyGlass()) return SGRGlassModeLegacy;
    return SGRGlassModeBlur;
}

static UIView *newShape(SGRGlassMode mode) {
    UIView *shape;
    switch (mode) {
        case SGRGlassModeLegacy:
            shape = [[SGLegacyGlassView alloc] initWithFrame:CGRectZero];
            break;
        case SGRGlassModeBlur:
            shape = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
            break;
        case SGRGlassModeSolid:
            shape = [UIView new];
            shape.backgroundColor = SGRSolidGlassFill();
            break;
    }
    shape.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    shape.userInteractionEnabled = NO;
    return shape;
}

#pragma mark - inside a control

static char kInsideModeKey, kFilmKey;

// The film that makes a shape prominent, inside the effect's own content view so the corners clip it.
static void keepFilm(UIView *shape, BOOL prominent, SGRGlassMode mode) {
    if (mode == SGRGlassModeSolid) {
        shape.backgroundColor = prominent ? [SGRSolidGlassFill() colorWithAlphaComponent:0.26] : SGRSolidGlassFill();
        return;
    }
    UIView *film = objc_getAssociatedObject(shape, &kFilmKey);
    if (!prominent) {
        film.hidden = YES;
        return;
    }
    UIView *content = [shape isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)shape).contentView
                     : [shape isKindOfClass:SGLegacyGlassView.class] ? ((SGLegacyGlassView *)shape).contentView
                     : shape;
    if (!film) {
        film = [UIView new];
        film.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        film.userInteractionEnabled = NO;
        film.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(shape, &kFilmKey, film, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    film.hidden = NO;
    if (film.superview != content) [content addSubview:film];
    // The effect's content view does not clip, so the film carries the shape's corners itself; square ones
    // drew a lighter rectangle around the playlist's Play capsule (harness, 2026-09-17).
    if (!CGRectEqualToRect(film.frame, content.bounds)) {
        film.frame = content.bounds;
        film.layer.cornerRadius = MIN(content.bounds.size.width, content.bounds.size.height) / 2;
        film.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

static UIView *glassInside(UIView *control, const void *key, CGSize size, BOOL capsule, BOOL prominent) {
    if (!control || !key) return nil;
    SGRGlassMode mode = glassMode();
    UIView *shape = objc_getAssociatedObject(control, key);
    if (shape && [objc_getAssociatedObject(shape, &kInsideModeKey) integerValue] != mode) {
        [shape removeFromSuperview];
        shape = nil;
    }
    if (!shape) {
        shape = newShape(mode);
        shape.accessibilityElementsHidden = YES;
        shape.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                               | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        objc_setAssociatedObject(shape, &kInsideModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(control, key, shape, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (shape.superview != control) [control addSubview:shape];
    // First among the control's subviews, so the glyph the control draws is genuinely after the shape in the
    // tree. The shape used to be added last and pushed back with zPosition -1 instead, which sorts the
    // compositing but not what glass takes for its backdrop: on the phone the glyph above it was captured
    // into it, so the button showed a soft ghost of its icon through the glass and no icon over it
    // (issue #39, iOS 26.1). The simulator's glass does not refract and shows neither order failing, so this
    // one is ordered the plain way rather than by depth. Re-asserted on every pass the caller makes, since a
    // control that rebuilds its content puts that in at index 0 too and would end up under the shape.
    if (control.subviews.firstObject != shape) [control insertSubview:shape atIndex:0];
    shape.hidden = size.width <= 0 || size.height <= 0;
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    if (!CGRectEqualToRect(shape.bounds, bounds)) {
        shape.bounds = bounds;
        SGShapeGlass(shape, MIN(size.width, size.height) / 2, capsule);
    }
    keepFilm(shape, prominent, mode);
    CGPoint middle = CGPointMake(CGRectGetMidX(control.bounds), CGRectGetMidY(control.bounds));
    if (!CGPointEqualToPoint(shape.center, middle)) shape.center = middle;
    return shape;
}

UIView *SGRGlassInside(UIView *control, const void *key, CGFloat side) {
    return glassInside(control, key, CGSizeMake(side, side), YES, NO);
}

UIView *SGRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent) {
    return glassInside(control, key, size, YES, prominent);
}

void SGRShowGlass(UIView *shape, BOOL shown) {
    if ([shape isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *glass = (UIVisualEffectView *)shape;
        if ((glass.effect != nil) != shown) glass.effect = shown ? SGGlassEffect() : nil;
    } else {
        shape.alpha = shown ? 1 : 0;
    }
}

#pragma mark - flat boxes and floating films

UIView *SGRGlassFlatBox(UIView *box, const void *key) {
    CGSize size = box.bounds.size;
    if (!box || size.width < 1 || size.height < 1) return nil;
    if (box.backgroundColor != UIColor.clearColor) box.backgroundColor = UIColor.clearColor;
    if (box.layer.cornerRadius != size.height / 2) box.layer.cornerRadius = size.height / 2;
    if (box.layer.cornerCurve != kCACornerCurveContinuous) box.layer.cornerCurve = kCACornerCurveContinuous;
    if (!box.layer.masksToBounds) box.layer.masksToBounds = YES;
    return SGRGlassCapsuleInside(box, key, size, NO);
}

// The legacy glass of a small control blurs at radius 2 and the old 16% white film over it left the bars
// nearly transparent: the page under the tab bar and the now playing card came through sharp and the labels
// on them were hard to read. A bar blurs like a sheet does and carries a dark body, so its glyphs and text sit
// on something even whatever is behind. Under Reduce Transparency the body is the solid fill alone.
static const CGFloat kBarBlur = 10;

UIView *SGRGlassFilm(UIView *host, const void *key, UIView *glass, CGFloat radius) {
    UIView *film = SGLazyChild(host, key, ^UIView *{
        UIView *view = [UIView new];
        view.userInteractionEnabled = NO;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.layer.masksToBounds = YES;
        return view;
    });
    // The dense body is the fallback's: on iOS 26 and later the pane is the system's own glass, and the faint
    // white film stays as it was.
    BOOL system = NO;
    if (@available(iOS 26.0, *)) system = YES;
    UIColor *body = system ? [UIColor colorWithWhite:1 alpha:0.16]
                  : SGRReduceTransparency() ? SGRSolidGlassFill() : [UIColor colorWithWhite:0.06 alpha:0.52];
    if (![film.backgroundColor isEqual:body]) film.backgroundColor = body;
    if (!system && [glass isKindOfClass:SGLegacyGlassView.class] && ((SGLegacyGlassView *)glass).blurRadius < kBarBlur) {
        ((SGLegacyGlassView *)glass).blurRadius = kBarBlur;
    }
    if (film.superview != host) [host insertSubview:film aboveSubview:glass];
    if (!CGRectEqualToRect(film.frame, glass.frame)) film.frame = glass.frame;
    if (film.layer.cornerRadius != radius) film.layer.cornerRadius = radius;
    return film;
}

#pragma mark - a sheet's own chrome

// Whether `view` is sheet chrome rather than a row or card in the sheet's own list: it sits under `root`
// (sgr_sheetChromeRoot) with no scroll view between. The same footprint stripSheetChrome clears, so a
// view built after the first strip (the queue's footer) is cleared on its own repaint all the same.
BOOL SGRIsSheetChromeArea(UIView *view, UIView *root) {
    if (!root) return NO;
    for (UIView *v = view; v; v = v.superview) {
        if (v != view && [v isKindOfClass:UIScrollView.class]) return NO;
        if (v == root) return YES;
    }
    return NO;
}

// A card the sheet draws on purpose, not a wrapper's leftover grey: the device picker's "this device" card
// and its Connect button (SwiftUI._UIGraphicsView with a fill and a radius, trees/continuous 2026-10-05).
// They are the sheet's content, and cleared they leave the picker a bare list with nothing marking the
// device that is playing.
BOOL SGRIsSheetCard(UIView *view) {
    if ([NSStringFromClass(view.class) hasPrefix:@"SwiftUI"]) return YES;
    return view.layer.cornerRadius >= 1 && view.bounds.size.height > 4 && view.bounds.size.width < 380;
}

// The device picker's cards are SwiftUI shapes painted an opaque #292929, which on the glass are the one
// grey left in the sheet. They become a translucent white, the same family as the Connect button's 10%.
CGColorRef SGRSheetCardFill(void) {
    static CGColorRef fill;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fill = CGColorRetain([UIColor colorWithWhite:1 alpha:0.12].CGColor); });
    return fill;
}

BOOL SGRIsSwiftUICard(UIView *view) {
    return [NSStringFromClass(view.class) hasPrefix:@"SwiftUI"];
}

static void tintCard(UIView *view) {
    if (SGRIsSwiftUICard(view) && SGRIsSheetSurface(view.layer.backgroundColor)) view.layer.backgroundColor = SGRSheetCardFill();
}

static void clearFill(UIView *view) {
    tintCard(view);
    if (!SGKeepsColor(view) && !SGRIsSheetCard(view) && SGIsVisibleColor(view.layer.backgroundColor)) view.layer.backgroundColor = NULL;
}

// The opaque dark grey Spotify paints a sheet's rows and wrappers with (#1F1F1F, trees/continuous 2026-10-05:
// the queue's QueueCell, TrackRowQueue.Cell, SessionModifiersView and the ⋯ menu's table). Not SGIsBaseSurface:
// that stops at 0.10 for the #121212 page black, and this grey is 0.12.
BOOL SGRIsSheetSurface(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID() || CGColorGetAlpha(color) < 0.95) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    if (n == 2) return c[0] <= 0.20;
    if (n < 3) return NO;
    return c[0] <= 0.20 && fabs(c[0] - c[1]) < 0.02 && fabs(c[1] - c[2]) < 0.02;
}

// A row of the sheet's own list: every view nearly as wide as the sheet that carries the grey goes clear, the
// cell itself and the stacks the element framework wraps its content in. Narrow ones stay (an avatar's
// placeholder square, a badge): they are their own paint, not a band.
static const CGFloat kSheetBandShare = 0.75;

static void clearListPaint(UIView *view, CGFloat wide, int depth) {
    if (!view || depth > 12 || wide < 1) return;   // wide 0: the sheet is not laid out yet; the next pass does it
    tintCard(view);
    if (!SGKeepsColor(view) && !SGRIsSheetCard(view) && view.bounds.size.width >= wide && SGRIsSheetSurface(view.layer.backgroundColor)) {
        // Written through the view so its own backgroundColor and the layer say the same thing.
        view.backgroundColor = UIColor.clearColor;
    }
    for (UIView *sub in view.subviews) clearListPaint(sub, wide, depth + 1);
}

void SGRClearSheetCellPaint(UIView *cell, UIView *root) {
    if (!cell || !root) return;
    clearListPaint(cell, root.bounds.size.width * kSheetBandShare, 0);
}

// Walked from the pane outward rather than by identifier, since sheets wrap their content a varying
// number of levels deep (the queue one, the ⋯ menu seven: its table sat one past the old cap of six and
// kept its grey). Any opaque fill goes: before the first list nothing here is a card, whatever grey
// Spotify paints it with. A scroll view or table is cleared itself, and so are the bands its rows paint
// (clearListPaint); its rows are otherwise left as every other list in the redesign leaves them
// (SGRRestyle.h). Gives up well down rather than walk into a sheet this has never seen.
static void stripSheetChrome(UIView *view, UIView *skip, CGFloat wide, int depth) {
    if (!view || view == skip || depth > 14) return;
    clearFill(view);
    if ([view isKindOfClass:UIScrollView.class]) {
        for (UIView *sub in view.subviews) clearListPaint(sub, wide, 0);
        return;
    }
    for (UIView *sub in view.subviews) stripSheetChrome(sub, skip, wide, depth + 1);
}

// A sheet is a big pane, and the glass of a small control is too thin for one: the page under it came through
// nearly sharp (blur 2) and took the eye off the sheet. So the pane blurs far more and carries a dark body
// and a hairline edge, which is what tells it from a plain blur -- the rim catching light, over a body dense
// enough to hold the content. Under Reduce Transparency the body is the solid fill alone.
static const CGFloat kSheetBlur = 10;
static char kSheetBodyKey, kSheetRimKey;

void SGRThickenSheetGlass(UIView *glass, CGFloat cornerRadius) {
    if ([glass isKindOfClass:SGLegacyGlassView.class]) ((SGLegacyGlassView *)glass).blurRadius = kSheetBlur;
    UIView *host = [glass isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)glass).contentView
                 : [glass isKindOfClass:SGLegacyGlassView.class] ? ((SGLegacyGlassView *)glass).contentView
                 : glass;
    UIView *body = SGLazyChild(host, &kSheetBodyKey, ^UIView *{
        UIView *view = [UIView new];
        view.userInteractionEnabled = NO;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        return view;
    });
    UIColor *tint = SGRReduceTransparency() ? SGRSolidGlassFill() : [UIColor colorWithWhite:1 alpha:0.24];
    if (![body.backgroundColor isEqual:tint]) body.backgroundColor = tint;
    if (!CGRectEqualToRect(body.frame, host.bounds)) body.frame = host.bounds;
    // The rim: one point of light along the top edge, fading down the sides, drawn over the body.
    UIView *rim = SGLazyChild(host, &kSheetRimKey, ^UIView *{
        UIView *view = [UIView new];
        view.userInteractionEnabled = NO;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        view.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        return view;
    });
    if (!CGRectEqualToRect(rim.frame, host.bounds)) rim.frame = host.bounds;
    if (rim.layer.cornerRadius != cornerRadius) rim.layer.cornerRadius = cornerRadius;
    if (body.superview == host && host.subviews.firstObject != body) [host sendSubviewToBack:body];
    if (rim.superview == host && host.subviews.lastObject != rim) [host bringSubviewToFront:rim];
}

static char kSheetDimKey;

void SGRDimSheetGlass(UIView *glass, CGFloat alpha) {
    UIView *host = [glass isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)glass).contentView
                 : [glass isKindOfClass:SGLegacyGlassView.class] ? ((SGLegacyGlassView *)glass).contentView
                 : glass;
    UIView *dim = SGLazyChild(host, &kSheetDimKey, ^UIView *{
        UIView *view = [UIView new];
        view.userInteractionEnabled = NO;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        return view;
    });
    UIColor *tint = SGRReduceTransparency() ? UIColor.blackColor : [UIColor colorWithWhite:0 alpha:alpha];
    if (![dim.backgroundColor isEqual:tint]) dim.backgroundColor = tint;
    if (!CGRectEqualToRect(dim.frame, host.bounds)) dim.frame = host.bounds;
    // Over the body, under the rim.
    UIView *body = objc_getAssociatedObject(host, &kSheetBodyKey);
    if (dim.superview != host) [host addSubview:dim];
    if (body.superview == host) [host insertSubview:dim aboveSubview:body];
    UIView *rim = objc_getAssociatedObject(host, &kSheetRimKey);
    if (rim.superview == host) [host bringSubviewToFront:rim];
}

UIView *SGRGlassSheetChrome(UIView *content) {
    static char kSheetChromeGlassKey;
    for (UIView *v = content; v; v = v.superview) {
        if (![v.accessibilityIdentifier isEqualToString:@"sheet-view"]) continue;
        UIView *glass = SGGlassFor(v, &kSheetChromeGlassKey);
        glass.frame = v.bounds;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        SGShapeGlass(glass, v.layer.cornerRadius, NO);
        SGRThickenSheetGlass(glass, v.layer.cornerRadius);
        if (v.layer.backgroundColor) v.layer.backgroundColor = NULL;
        CGFloat wide = v.bounds.size.width * kSheetBandShare;
        for (UIView *sub in v.subviews) stripSheetChrome(sub, glass, wide, 0);
        // Spotify repaints the grey on later passes; SGRRepaint.x keeps clearing it under this root.
        if (sgr_sheetChromeRoot != v) sgr_sheetChromeRoot = v;
        return glass;
    }
    return nil;
}
