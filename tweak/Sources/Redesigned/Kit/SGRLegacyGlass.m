#import "Core/SGCore.h"
#import "SGRLegacyGlass.h"
#import "SGRGlass.h"
#import "SGRRestyle.h"
#import "SGRTokens.h"
#import <objc/runtime.h>
#import <objc/message.h>

__weak UIView *sgr_sheetChromeRoot = nil;

#pragma mark - flat boxes and floating films

// The view `make` builds, made once and kept on `host` under `key`. Not added to the hierarchy.
static UIView *lazyChild(UIView *host, const void *key, UIView *(^make)(void)) {
    UIView *v = objc_getAssociatedObject(host, key);
    if (!v) {
        v = make();
        objc_setAssociatedObject(host, key, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return v;
}

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
    UIView *film = lazyChild(host, key, ^UIView *{
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
    UIView *body = lazyChild(host, &kSheetBodyKey, ^UIView *{
        UIView *view = [UIView new];
        view.userInteractionEnabled = NO;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        return view;
    });
    UIColor *tint = SGRReduceTransparency() ? SGRSolidGlassFill() : [UIColor colorWithWhite:1 alpha:0.24];
    if (![body.backgroundColor isEqual:tint]) body.backgroundColor = tint;
    if (!CGRectEqualToRect(body.frame, host.bounds)) body.frame = host.bounds;
    // The rim: one point of light along the top edge, fading down the sides, drawn over the body.
    UIView *rim = lazyChild(host, &kSheetRimKey, ^UIView *{
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
        // Spotify repaints the grey on later passes; SGRLegacyRepaint.x keeps clearing it under this root.
        if (sgr_sheetChromeRoot != v) sgr_sheetChromeRoot = v;
        return glass;
    }
    return nil;
}

#pragma mark - the page's pinned back button

static const CGFloat kCornerSide = 16;   // as SGRPinnedMore's

// Over the page's list and its header both, and put back on top whenever Spotify adds to the page.
static void keepOnTop(UIView *page, UIView *button) {
    if (button.superview != page) [page addSubview:button];
    else if (page.subviews.lastObject != button) [page bringSubviewToFront:button];
}

// Level with the window's safe area at the top, kCornerSide in from the leading edge. Measured in the window
// and converted back, never from the page's own safe area: a page under a navigation bar counts the bar
// into its inset, so the playlist's read 116 where the window's reads 62.
static void placeInCorner(UIView *page, UIView *button) {
    UIWindow *window = page.window;
    UIView *space = window ?: page;
    CGFloat side = SGRGlassCircleSize;
    CGRect frame = CGRectMake(kCornerSide, space.safeAreaInsets.top, side, side);
    if (window) frame = [page convertRect:frame fromView:nil];
    if (!CGRectIsEmpty(frame) && !CGRectEqualToRect(button.frame, frame)) button.frame = frame;
}

// Hides Spotify's own back button once it is mirrored: a mask survives Spotify showing it again, which
// -[UIView setHidden:] does not, and with no interaction and no accessibility only the mirror is seen or
// fired.
static void concealBack(UIView *source) {
    if (!source) return;
    if (!source.layer.hidden) source.layer.hidden = YES;
    if (!source.layer.mask) source.layer.mask = [CALayer layer];
    if (source.userInteractionEnabled) source.userInteractionEnabled = NO;
    source.accessibilityElementsHidden = YES;
}

SGRMirrorButton *SGRPinnedBack(UIView *page, UIView *searchRoot) {
    static char kSourceKey, kButtonKey;
    if (!page) return nil;
    UIView *source = SGRFindByIdentifier(searchRoot, @"Components.Header.UI.BackButton", &kSourceKey);
    SGRMirrorButton *button = objc_getAssociatedObject(page, &kButtonKey);
    if (!button) {
        button = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
        button.fallbackGlyph = [UIImage systemImageNamed:@"chevron.left"];
        button.glyphColor = SGRPrimary();
        button.accessibilityLabel = source.accessibilityLabel ?: @"Back";
        objc_setAssociatedObject(page, &kButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    keepOnTop(page, button);
    concealBack(source);
    if (source) [button feedFrom:source];
    if (button.hidden != (source == nil)) button.hidden = source == nil;
    placeInCorner(page, button);
    return button;
}

#pragma mark - watching a layout the author's SGRObserveLayout cannot

static char kLegacyLayoutKey;
static BOOL sg_legacyReporting;

static void legacyReportLayout(UIView *view) {
    if (sg_legacyReporting) return;
    void (^block)(UIView *) = objc_getAssociatedObject(view, &kLegacyLayoutKey);
    if (!block) return;
    sg_legacyReporting = YES;
    block(view);
    sg_legacyReporting = NO;
}

static BOOL legacyOverrideOnClass(Class cls, SEL selector, id (^make)(IMP replaced)) {
    if (!cls || !selector) return NO;
    // Never the class KVO made for one instance: it is swapped away again when the last observer goes, and
    // the override with it. Everything else here is a class Spotify itself wrote.
    if (strncmp(class_getName(cls), "NSKVONotifying_", 15) == 0) return NO;
    // Done already? A class is an object too, and a selector is a pointer unique to its name, so the class
    // carries its own mark per selector -- a plain lookup, since callers ask again on every pass they make.
    if (objc_getAssociatedObject(cls, (void *)selector)) return YES;

    Method inherited = class_getInstanceMethod(cls, selector);
    if (!inherited) return NO;
    Method own = nil;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) own = methods[i];
    }
    free(methods);
    IMP replaced = own ? method_getImplementation(own)
                       : class_getMethodImplementation(class_getSuperclass(cls), selector);
    if (!replaced) return NO;

    IMP override = imp_implementationWithBlock(make(replaced));
    if (own) method_setImplementation(own, override);
    else if (!class_addMethod(cls, selector, override, method_getTypeEncoding(inherited))) return NO;
    objc_setAssociatedObject(cls, (void *)selector, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

// SGRObserveLayout (Kit/SGRRestyle.h) subclasses the instance, which one of Spotify's own Swift classes (a
// library filter chip) does not allow. Then the class itself carries the override, which only ever reports
// the instances that asked. Kept here rather than in SGRRestyle.m so that file stays the author's.
BOOL SGRLegacyObserveLayout(UIView *view, void (^laidOut)(UIView *view)) {
    if (![view isKindOfClass:UIView.class]) return NO;
    if (SGRObserveLayout(view, laidOut)) return YES;
    objc_setAssociatedObject(view, &kLegacyLayoutKey, laidOut, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return legacyOverrideOnClass(object_getClass(view), @selector(layoutSubviews), ^id(IMP replaced) {
        return ^(UIView *self) {
            ((void (*)(id, SEL))replaced)(self, @selector(layoutSubviews));
            legacyReportLayout(self);
        };
    });
}
