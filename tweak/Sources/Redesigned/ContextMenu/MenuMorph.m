// The player's ⋯ menu below iOS 26 opens the way iOS 26's does: the button flies down to where the menu's middle
// will be and fades into it, while the menu grows out of the button's middle on the way. UIKit's own opening (the
// menu unrolled from its corner) is taken off as the morph starts, and the menu is held unseen until then, so the
// morph is the whole opening. Closing flies the button back out of the menu's middle to its place.
//
// What moves is the menu's own view (_UIContextMenuView), not its list: UIKit unrolls the list through a mask on that
// view, and a list moved inside it is cut off by the mask and the morph is not seen.
//
// The source is told before UIKit presents (SGRMenuMorphPrepare, from the touch down that asks for the menu). The
// morph starts on the first layout with a size of the menu's list (ContextMenuGlass.x), before its first frame, or,
// should that layout not come while the source waits, as the menu is shown (SGRMenuMorphShown), a frame late. A
// submenu's list comes later and finds nothing waiting. What it did or why it did not is logged.
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

static void note(NSString *what) {
    static NSMutableSet<NSString *> *said;
    if (!said) said = [NSMutableSet set];
    if ([said containsObject:what]) return;
    [said addObject:what];
    SGLog(@"menu morph: %@", what);
}

static BOOL morphs(void) {
    return SGBelowiOS26() && !SGRReduceMotion();
}

void SGRMenuMorphPrepare(UIView *source) {
    if (!SGBelowiOS26()) return;
    if (SGRReduceMotion()) { note(@"off, Reduce Motion is on"); return; }
    if (!source.window) { note(@"no ⋯ in a window to start from"); return; }
    sPending = source;
    sPendingAt = CACurrentMediaTime();
    note(@"armed by the ⋯'s touch");
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

// The menu view held unseen from its first moment in a window until the morph starts on it, so neither UIKit's own
// opening nor a menu at full size shows for the frames before (device, 2026-10-23: two frames of a narrow sliver
// beside the button, then the menu shrunk into the button and grown again). Given back after kHoldLimit whatever
// happens, so a morph that never starts never leaves the menu unseen.
static const CFTimeInterval kHoldLimit = 0.3;
static __weak UIView *sHeld;

static void releaseHeld(void) {
    UIView *held = sHeld;
    sHeld = nil;
    if (held && held.layer.opacity < 1) held.layer.opacity = 1;
}

void SGRMenuMorphHold(UIView *list) {
    UIView *menu = list.superview;
    if (!sPending || !menu || sHeld == menu || CACurrentMediaTime() - sPendingAt > kMorphWait || !morphs()) return;
    sHeld = menu;
    menu.layer.opacity = 0;
    __weak UIView *weakMenu = menu;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHoldLimit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sHeld != weakMenu) return;
        note(@"the menu was held for its morph, which did not start: shown as UIKit opens it");
        releaseHeld();
    });
}

// UIKit's own opening of the menu view (the menu unrolled from its corner through the view's mask, and whatever it
// animates on the view itself), taken off: the morph is the whole opening. Its model values are the opened menu's,
// so what is left is the menu as it ends up.
static void stopUIKitOpening(UIView *menu) {
    NSMutableArray<CALayer *> *layers = [NSMutableArray arrayWithObject:menu.layer];
    if (menu.layer.mask) [layers addObject:menu.layer.mask];
    for (UIView *sub in menu.subviews) {
        [layers addObject:sub.layer];
        if (sub.layer.mask) [layers addObject:sub.layer.mask];
    }
    for (CALayer *layer in layers) {
        for (NSString *key in layer.animationKeys) {
            if (![key hasPrefix:@"sgr.morph."]) [layer removeAnimationForKey:key];
        }
    }
}

static void morph(UIView *list, NSString *how) {
    UIView *source = sPending;
    if (!source.window || CACurrentMediaTime() - sPendingAt > kMorphWait || !morphs()) {
        sPending = nil;
        releaseHeld();
        note(@"the ⋯ went away before its menu came");
        return;
    }
    UIView *menu = list.superview;
    UIView *space = menu.superview;
    // Not yet: a later layout of the list, before its first frame, has the size (and the menu stays held till then).
    if (!space || list.bounds.size.width < 1 || list.bounds.size.height < 1) { note(@"the menu had no size to grow to yet"); return; }
    sPending = nil;
    stopUIKitOpening(menu);

    // Where the button's middle is and where the list's will be, in the space the menu view stands in.
    CGPoint from = [source convertPoint:CGPointMake(CGRectGetMidX(source.bounds), CGRectGetMidY(source.bounds)) toCoordinateSpace:space];
    CGPoint to = [list convertPoint:CGPointMake(CGRectGetMidX(list.bounds), CGRectGetMidY(list.bounds)) toCoordinateSpace:space];
    CGSize size = list.bounds.size, button = source.bounds.size;
    CGFloat sx = MAX(kMorphMinScale, button.width / size.width), sy = MAX(kMorphMinScale, button.height / size.height);
    // The menu view scales about its own middle, which need not be the list's: the move is what puts the list's
    // middle on the button's at the start.
    CGPoint middle = menu.center;
    CALayer *layer = menu.layer;
    addSpring(layer, @"transform.translation.x", from.x - middle.x - sx * (to.x - middle.x));
    addSpring(layer, @"transform.translation.y", from.y - middle.y - sy * (to.y - middle.y));
    addSpring(layer, @"transform.scale.x", sx - 1);
    addSpring(layer, @"transform.scale.y", sy - 1);
    if (sHeld == menu) releaseHeld();

    // The button into the menu's middle: it goes on the same spring and is gone before it gets there. Left at its
    // place unseen, by alpha (a hidden view in Spotify's stacks crashes, AGENTS.md).
    CGPoint target = [space convertPoint:to toCoordinateSpace:source.superview];
    CGPoint by = CGPointMake(target.x - source.center.x, target.y - source.center.y);
    sFlown = source;
    sFlownBy = by;
    [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ source.transform = CGAffineTransformMakeTranslation(by.x, by.y); } completion:^(BOOL finished) {
        if (sFlown == source && source.alpha < 0.01) source.transform = CGAffineTransformIdentity;
    }];
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ source.alpha = 0; } completion:nil];
    note([NSString stringWithFormat:@"grown %@, from %@ to the menu in %@", how, NSStringFromCGPoint(from), NSStringFromClass(menu.class)]);
}

void SGRMenuMorphOpen(UIView *list) {
    if (sPending) morph(list, @"from the list's first layout");
}

// The first list in a window: the top menu's, a submenu's is made later.
static UIView *visibleList(void) {
    Class listClass = NSClassFromString(@"_UIContextMenuListView");
    __block UIView *found = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            SGForEachView(window, ^(UIView *v) {
                if (!found && [v isKindOfClass:listClass] && v.bounds.size.width >= 1) found = v;
            });
            if (found) return found;
        }
    }
    return nil;
}

void SGRMenuMorphShown(void) {
    if (!sPending) {
        if (!sFlown && morphs()) note(@"the menu was shown with nothing armed (or already grown)");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sPending) return;
        UIView *list = visibleList();
        if (list) morph(list, @"as the menu was shown");
        if (!list || sPending) {
            sPending = nil;
            releaseHeld();
            note(list ? @"the menu shown had no size to grow to" : @"no menu list found to grow");
        }
    });
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
