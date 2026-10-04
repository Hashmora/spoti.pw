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

UIView *SGRGlassFilm(UIView *host, const void *key, UIView *glass, CGFloat radius) {
    UIView *film = SGLazyChild(host, key, ^UIView *{
        UIView *view = [UIView new];
        view.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        view.userInteractionEnabled = NO;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.layer.masksToBounds = YES;
        return view;
    });
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
        if ([v isKindOfClass:UIScrollView.class]) return NO;
        if (v == root) return YES;
    }
    return NO;
}

static void clearFill(UIView *view) {
    if (!SGKeepsColor(view) && SGIsVisibleColor(view.layer.backgroundColor)) view.layer.backgroundColor = NULL;
}

// Walked from the pane outward rather than by identifier, since sheets wrap their content a varying
// number of levels deep (the ⋯ menu two, the queue one). Any opaque fill goes: before the first list
// nothing here is a card, whatever grey Spotify paints it with. A scroll view or table is cleared itself
// and not entered, so its rows stay as every other list in the redesign leaves them (SGRRestyle.h).
// Gives up a few levels down rather than walk into a sheet this has never seen.
static void stripSheetChrome(UIView *view, UIView *skip, int depth) {
    if (!view || view == skip || depth > 6) return;
    clearFill(view);
    if ([view isKindOfClass:UIScrollView.class]) return;
    for (UIView *sub in view.subviews) stripSheetChrome(sub, skip, depth + 1);
}

UIView *SGRGlassSheetChrome(UIView *content) {
    static char kSheetChromeGlassKey;
    for (UIView *v = content; v; v = v.superview) {
        if (![v.accessibilityIdentifier isEqualToString:@"sheet-view"]) continue;
        UIView *glass = SGGlassFor(v, &kSheetChromeGlassKey);
        glass.frame = v.bounds;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        SGShapeGlass(glass, v.layer.cornerRadius, NO);
        if (v.layer.backgroundColor) v.layer.backgroundColor = NULL;
        for (UIView *sub in v.subviews) stripSheetChrome(sub, glass, 0);
        // Spotify repaints the grey on later passes; SGRRepaint.x keeps clearing it under this root.
        if (sgr_sheetChromeRoot != v) sgr_sheetChromeRoot = v;
        return glass;
    }
    return nil;
}
