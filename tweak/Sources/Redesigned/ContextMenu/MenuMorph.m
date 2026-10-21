// The player's ⋯ menu below iOS 26 opens the way iOS 26's does: the button flies down to where the menu's middle
// will be and fades into it, while the menu grows out of the button's middle on the way. UIKit's own opening
// (a fade and a scale from the menu's corner) still runs under it; the morph is added on top of it, additively, so
// neither has to know of the other. Closing flies the button back out of the menu's middle to its place.
//
// The source is told before UIKit presents (SGRMenuMorphPrepare, from the touch down that asks for the menu), and the
// morph starts on the first layout of the menu's list with a size (ContextMenuGlass.x), before its first frame is drawn.
// A submenu's list comes later and finds nothing waiting.
//
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "ContextMenu.h"

// How long a prepared source waits for its menu: a touch down that opened none is forgotten.
static const CFTimeInterval kMorphWait = 1.0;
// The menu's spring: quick, with a hint of overshoot, as the system's.
static const CGFloat kMorphMass = 1, kMorphStiffness = 320, kMorphDamping = 30;
// The smallest the menu starts at, so its rows are not drawn as a line on their way out of the button.
static const CGFloat kMorphMinScale = 0.12;

static __weak UIView *sPending;
static CFTimeInterval sPendingAt;
// The button that flew into the menu, and how far, so closing brings it back from there.
static __weak UIView *sFlown;
static CGPoint sFlownBy;

static BOOL morphs(void) {
    return SGBelowiOS26() && !SGRReduceMotion();
}

void SGRMenuMorphPrepare(UIView *source) {
    if (!morphs() || !source.window) return;
    sPending = source;
    sPendingAt = CACurrentMediaTime();
}

static void addSpring(CALayer *layer, NSString *path, CGFloat from) {
    CASpringAnimation *a = [CASpringAnimation animationWithKeyPath:path];
    a.mass = kMorphMass;
    a.stiffness = kMorphStiffness;
    a.damping = kMorphDamping;
    a.fromValue = @(from);
    a.toValue = @0;
    a.additive = YES;
    a.duration = a.settlingDuration;
    a.fillMode = kCAFillModeBackwards;
    [layer addAnimation:a forKey:[@"sgr.morph." stringByAppendingString:path]];
}

void SGRMenuMorphOpen(UIView *list) {
    UIView *source = sPending;
    if (!source || !list.superview || list.bounds.size.width < 1 || list.bounds.size.height < 1) return;
    sPending = nil;
    if (!source.window || CACurrentMediaTime() - sPendingAt > kMorphWait || !morphs()) return;

    UIView *host = list.superview;
    CGPoint from = [source convertPoint:CGPointMake(CGRectGetMidX(source.bounds), CGRectGetMidY(source.bounds)) toCoordinateSpace:host];
    CGPoint to = list.center;
    CGSize size = list.bounds.size, button = source.bounds.size;

    // The menu out of the button's middle.
    CALayer *layer = list.layer;
    addSpring(layer, @"transform.translation.x", from.x - to.x);
    addSpring(layer, @"transform.translation.y", from.y - to.y);
    addSpring(layer, @"transform.scale.x", MAX(kMorphMinScale, button.width / size.width) - 1);
    addSpring(layer, @"transform.scale.y", MAX(kMorphMinScale, button.height / size.height) - 1);

    // The button into the menu's middle: it goes on the same spring and is gone before it gets there. Left at its
    // place unseen, by alpha (a hidden view in Spotify's stacks crashes, AGENTS.md).
    CGPoint target = [host convertPoint:to toCoordinateSpace:source.superview];
    CGPoint by = CGPointMake(target.x - source.center.x, target.y - source.center.y);
    sFlown = source;
    sFlownBy = by;
    [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ source.transform = CGAffineTransformMakeTranslation(by.x, by.y); } completion:^(BOOL finished) {
        if (sFlown == source && source.alpha < 0.01) source.transform = CGAffineTransformIdentity;
    }];
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ source.alpha = 0; } completion:nil];
}

void SGRMenuMorphClose(UIView *source) {
    if (sPending == source) sPending = nil;
    if (!source || sFlown != source) return;
    sFlown = nil;
    CGPoint by = sFlownBy;
    [source.layer removeAllAnimations];
    [UIView performWithoutAnimation:^{ source.transform = CGAffineTransformMakeTranslation(by.x, by.y); }];
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ source.transform = CGAffineTransformIdentity; } completion:nil];
    [UIView animateWithDuration:0.22 delay:0.06 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ source.alpha = 1; } completion:nil];
}
