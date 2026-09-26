#import "SGGlass.h"
#import "SGLegacyGlass.h"
#import "SGPrefs.h"
#import "SGRuntime.h"

// +effectWithStyle: is the only initialiser UIGlassEffect has; a bare -init leaves the material
// unresolved and the pane renders as a plain blur, while the capsule shape, which is the view's
// own property, still comes out right. Spotify's own Reprise glass builds its effect the same way.
UIVisualEffect *SGGlassEffect(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if ([glass respondsToSelector:@selector(effectWithStyle:)]) return [glass effectWithStyle:0];
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
}

// The legacy view stands in only below iOS 26 (UIGlassEffect covers that and up on its own), only
// with the switch on, and only where SGLegacyGlassAvailable() finds the private API it leans on.
// Exported (see SGGlass.h) so SGRGlass.m asks this instead of re-deriving its own answer.
BOOL SGUseLegacyGlass(void) {
    if (@available(iOS 26.0, *)) return NO;
    return SGFlag(SGKeyLegacyGlass, NO) && SGLegacyGlassAvailable();
}

static UIView *newPane(void) {
    UIView *glass;
    if (SGUseLegacyGlass()) {
        glass = [[SGLegacyGlassView alloc] initWithFrame:CGRectZero];
    } else {
        glass = [[UIVisualEffectView alloc] initWithEffect:SGGlassEffect()];
    }
    glass.userInteractionEnabled = NO;
    // A pane goes in at index 0, but a host that rebuilds its content puts that in at index 0 too
    // and the pane would end up over it. Depth keeps a pane behind whatever the host draws.
    glass.layer.zPosition = -1;
    return glass;
}

UIView *SGGlassFor(UIView *host, const void *key) {
    UIView *glass = objc_getAssociatedObject(host, key);
    if (!glass) {
        glass = newPane();
        objc_setAssociatedObject(host, key, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != host) [host insertSubview:glass atIndex:0];
    return glass;
}

static char kPanesKey;

UIView *SGGlassAt(UIView *host, NSUInteger index) {
    NSMutableArray<UIView *> *panes = objc_getAssociatedObject(host, &kPanesKey);
    if (!panes) {
        panes = [NSMutableArray array];
        objc_setAssociatedObject(host, &kPanesKey, panes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    while (panes.count <= index) [panes addObject:newPane()];
    UIView *glass = panes[index];
    glass.hidden = NO;
    if (glass.superview != host) [host insertSubview:glass atIndex:0];
    return glass;
}

void SGHideGlassFrom(UIView *host, NSUInteger count) {
    NSArray<UIView *> *panes = objc_getAssociatedObject(host, &kPanesKey);
    for (NSUInteger i = count; i < panes.count; i++) panes[i].hidden = YES;
}

void SGShapeGlass(UIView *glass, CGFloat radius, BOOL capsule) {
    if ([glass isKindOfClass:SGLegacyGlassView.class]) {
        // The header's own guidance (SGLegacyGlass.h): NO for flat chrome and round controls alike.
        [(SGLegacyGlassView *)glass updateWithSize:glass.bounds.size cornerRadius:radius capsule:capsule clear:NO];
        return;
    }
    Class config = NSClassFromString(@"UICornerConfiguration");
    Class cornerRadius = NSClassFromString(@"UICornerRadius");
    id shape = nil;
    if (config && [glass respondsToSelector:@selector(setCornerConfiguration:)]) {
        if (capsule && [config respondsToSelector:@selector(capsuleConfiguration)]) {
            shape = [config capsuleConfiguration];
        } else if ([config respondsToSelector:@selector(configurationWithUniformRadius:)] && [cornerRadius respondsToSelector:@selector(fixedRadius:)]) {
            shape = [config configurationWithUniformRadius:[cornerRadius fixedRadius:radius]];
        }
    }
    if (shape) {
        [glass setCornerConfiguration:shape];
        glass.clipsToBounds = NO;
    } else {
        glass.layer.cornerRadius = capsule ? glass.bounds.size.height / 2 : radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = YES;
    }
}
