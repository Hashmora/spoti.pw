#import "Core/SGCore.h"
#import "SGRGlass.h"
#import "SGRTokens.h"
#import "SGRRestyle.h"

typedef NS_ENUM(NSInteger, SGRGlassMode) {
    SGRGlassModeGlass,
    SGRGlassModeLegacy,
    SGRGlassModeBlur,
    SGRGlassModeSolid,
};

// Below iOS 26 a plain system blur reads as almost nothing over Spotify's near-black chrome, so the
// same "Legacy Liquid Glass" switch that backs NowPlayingBar and the navbar (Core/SGGlass.m) is used
// here too, for the header's round buttons and the rest of the Kit's capsules.
static SGRGlassMode glassMode(void) {
    if (SGRReduceTransparency()) return SGRGlassModeSolid;
    if (@available(iOS 26.0, *)) return SGRGlassModeGlass;
    if (SGFlag(SGKeyLegacyGlass, NO) && SGLegacyGlassAvailable()) return SGRGlassModeLegacy;
    return SGRGlassModeBlur;
}

static UIView *newShape(SGRGlassMode mode) {
    UIView *shape;
    switch (mode) {
        case SGRGlassModeGlass:
            shape = [[UIVisualEffectView alloc] initWithEffect:SGGlassEffect()];
            break;
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

#pragma mark - a header's back button

static const CGFloat kHeaderBackCircle = 44;

static UIView *headerBackBoxIn(UIView *back) {
    __block UIView *found = nil;
    SGForEachView(back, ^(UIView *v) {
        if (!found && [NSStringFromClass(v.class) containsString:@"HeaderToolbarActionBackgroundView"]) found = v;
    });
    return found;
}

UIView *SGRGlassHeaderBack(UIView *page) {
    static char kBackKey, kBackGlassKey;
    UIView *back = SGRFindByIdentifier(page, @"Components.Header.UI.BackButton", &kBackKey);
    if (!back) return nil;
    UIView *box = headerBackBoxIn(back);
    if (box && fabs(box.bounds.size.width - kHeaderBackCircle) > 0.5) {
        CGPoint center = box.center;
        box.bounds = CGRectMake(0, 0, kHeaderBackCircle, kHeaderBackCircle);
        box.center = center;
        box.layer.cornerRadius = kHeaderBackCircle / 2;
        box.layer.cornerCurve = kCACornerCurveContinuous;
    }
    // Spotify's own box if there is one, glassed in the box's own place rather than the wider button's;
    // the button otherwise, for a build that ever changes how it draws the button and stops giving it one.
    return SGRGlassInside(box ?: back, &kBackGlassKey, kHeaderBackCircle);
}

#pragma mark - a sheet's own chrome

// Spotify's #1F1F1F sheet grey, one tick above SGIsBaseSurface's own 0.10 -- which keeps this exact grey
// wherever it draws a placeholder or a real card (SGRRepaint.x) -- since a sheet is its own closed box,
// not a field the rest of the page reads a card against.
static BOOL isSheetChromeFill(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID() || CGColorGetAlpha(color) < 0.95) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    if (n < 3) return NO;
    return c[0] <= 0.14 && fabs(c[0] - c[1]) < 0.02 && fabs(c[1] - c[2]) < 0.02;
}

// Walked from the pane outward rather than by identifier: the ⋯ sheet wraps its content two levels deep
// (context-menu-view, context-menu-main-view) and the queue's one (its own LayoutOnlyView's child), and
// nothing says a third sheet wraps it the same number of times. Stops at the first scroll view or table,
// leaving its rows exactly as every other list in the redesign leaves theirs (SGRRestyle.h), and gives up
// a few levels down rather than walking into a sheet this has never seen.
static void stripSheetChrome(UIView *view, UIView *skip, int depth) {
    if (!view || view == skip || depth > 6) return;
    if ([view isKindOfClass:UIScrollView.class]) return;
    if (!SGKeepsColor(view) && isSheetChromeFill(view.layer.backgroundColor)) view.layer.backgroundColor = NULL;
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
        return glass;
    }
    return nil;
}
