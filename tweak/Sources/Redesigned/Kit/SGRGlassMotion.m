#import "SGRGlassMotion.h"
#import "Core/SGCore.h"
#import "SGRTokens.h"

// How long a noted control waits for what replaces it: the two are shown and hidden in one pass of Spotify's, a turn of
// the run loop apart at most, and a morph from a control that went long ago would fly from nowhere.
static const CFTimeInterval kLeavingLife = 0.4;
// The shape's spring and its fade (the recording: the new controls are whole about 0.2 s after the tap, settled by 0.35).
static const NSTimeInterval kMorphDuration = 0.38, kMorphFadeDelay = 0.2, kMorphFadeDuration = 0.16;
static const CGFloat kMorphDamping = 0.8;
// The arriving control's own drawing comes in under the shape, from a little smaller.
static const NSTimeInterval kArriveDelay = 0.08, kArriveDuration = 0.22;
static const CGFloat kArriveScale = 0.9;
// A bar's controls, one after another.
static const NSTimeInterval kBarStagger = 0.04;
static const CGFloat kBarScale = 0.86;

static CGRect sLeavingRect;
static CGFloat sLeavingRadius;
static CFTimeInterval sLeavingAt;

static BOOL motionOn(void) {
    if (@available(iOS 26.0, *)) return NO;
    return SGUseLegacyGlass() && !SGRReduceMotion();
}

static BOOL onScreen(UIView *view) {
    return view.window && !view.hidden && view.alpha > 0.01 && view.bounds.size.width >= 1 && view.bounds.size.height >= 1;
}

// The corners a control is drawn with: its layer's, or a capsule's when it has none.
static CGFloat radiusOf(UIView *view) {
    CGFloat half = view.bounds.size.height / 2;
    CGFloat radius = view.layer.cornerRadius;
    return radius > 0 ? MIN(radius, half) : half;
}

// Fades `layer` in from nothing and grows it from `scale`, by animations of its own: the model stays as it is.
static void arrive(CALayer *layer, CFTimeInterval delay, CGFloat scale) {
    CFTimeInterval start = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0;
    fade.toValue = @(layer.opacity);
    fade.duration = kArriveDuration;
    fade.beginTime = start;
    fade.fillMode = kCAFillModeBackwards;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [layer addAnimation:fade forKey:@"sgr.arrive.fade"];
    CASpringAnimation *grow = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
    grow.fromValue = @(scale);
    grow.toValue = @1;
    grow.stiffness = 320;
    grow.damping = 26;
    grow.duration = grow.settlingDuration;
    grow.beginTime = start;
    grow.fillMode = kCAFillModeBackwards;
    [layer addAnimation:grow forKey:@"sgr.arrive.grow"];
}

void SGRGlassNoteLeaving(UIView *view) {
    if (!motionOn() || !onScreen(view)) return;
    sLeavingRect = [view convertRect:view.bounds toView:nil];
    sLeavingRadius = radiusOf(view);
    sLeavingAt = CACurrentMediaTime();
}

void SGRGlassMorphFromLeaving(UIView *to, SGRGlassMaker glass) {
    if (!motionOn() || !to || !glass || !sLeavingAt || CACurrentMediaTime() - sLeavingAt > kLeavingLife) return;
    CGRect start = sLeavingRect;
    CGFloat startRadius = sLeavingRadius;
    sLeavingAt = 0;
    // Spotify lays the header out after it has shown and hidden its controls: the shape ends where that puts `to`.
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = to.window;
        if (!onScreen(to)) return;
        [window layoutIfNeeded];
        CGRect end = [to convertRect:to.bounds toView:nil];
        if (CGRectEqualToRect(CGRectIntegral(start), CGRectIntegral(end))) return;
        CGFloat endRadius = radiusOf(to);

        UIView *shape = [[UIView alloc] initWithFrame:start];
        shape.userInteractionEnabled = NO;
        shape.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        shape.clipsToBounds = YES;
        shape.layer.cornerRadius = startRadius;
        shape.layer.cornerCurve = kCACornerCurveContinuous;
        UIView *pane = glass(shape);
        if (!pane) return;
        // The pane is as big as the larger of the two shapes and kept in the middle of the moving one, which clips it:
        // resized with it, it would take its new size at once and leave the shape bare while it grows.
        pane.autoresizingMask = UIViewAutoresizingNone;
        pane.bounds = CGRectMake(0, 0, MAX(start.size.width, end.size.width), MAX(start.size.height, end.size.height));
        pane.center = CGPointMake(start.size.width / 2, start.size.height / 2);
        SGShapeGlass(pane, MIN(startRadius, endRadius), NO);
        [window addSubview:shape];

        arrive(to.layer, kArriveDelay, kArriveScale);
        [UIView animateWithDuration:kMorphDuration delay:0 usingSpringWithDamping:kMorphDamping initialSpringVelocity:0
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            shape.frame = end;
            shape.layer.cornerRadius = endRadius;
            pane.center = CGPointMake(end.size.width / 2, end.size.height / 2);
        } completion:nil];
        [UIView animateWithDuration:kMorphFadeDuration delay:kMorphFadeDelay options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ shape.alpha = 0; }
                         completion:^(BOOL finished) { [shape removeFromSuperview]; }];
    });
}

// The controls of a bar: the UIControls in it, outermost first, in the order they read.
static void collectControls(UIView *view, NSMutableArray<UIView *> *into, int depth) {
    if (depth > 6 || !onScreen(view)) return;
    if ([view isKindOfClass:UIControl.class] && depth > 0) {
        [into addObject:view];
        return;
    }
    for (UIView *sub in view.subviews) collectControls(sub, into, depth + 1);
}

void SGRGlassBarAppear(UIView *bar) {
    if (!motionOn() || !bar) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!onScreen(bar)) return;
        [bar layoutIfNeeded];
        NSMutableArray<UIView *> *controls = [NSMutableArray array];
        collectControls(bar, controls, 0);
        if (!controls.count) {
            arrive(bar.layer, 0, kBarScale);
            return;
        }
        [controls sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            CGFloat ax = [a convertPoint:CGPointZero toView:nil].x, bx = [b convertPoint:CGPointZero toView:nil].x;
            return ax < bx ? NSOrderedAscending : ax > bx ? NSOrderedDescending : NSOrderedSame;
        }];
        [controls enumerateObjectsUsingBlock:^(UIView *control, NSUInteger i, BOOL *stop) {
            arrive(control.layer, i * kBarStagger, kBarScale);
        }];
    });
}
