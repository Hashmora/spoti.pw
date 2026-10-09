#import "PGGlass.h"
#import "PGRuntime.h"

// +effectWithStyle: is the only initialiser UIGlassEffect has; a bare -init leaves the material
// unresolved and the pane renders as a plain blur, while the capsule shape, which is the view's
// own property, still comes out right. Spotify's own Reprise glass builds its effect the same way.
UIVisualEffect *PGGlassEffect(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if ([glass respondsToSelector:@selector(effectWithStyle:)]) return [glass effectWithStyle:0];
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
}

BOOL PGUseLegacyGlass(void) {
    if (@available(iOS 26.0, *)) return NO;
    return PGLegacyGlassAvailable();
}

static UIView *newPane(void) {
    UIView *glass;
    if (PGUseLegacyGlass()) {
        glass = [[PGLegacyGlassView alloc] initWithFrame:CGRectZero];
    } else {
        glass = [[UIVisualEffectView alloc] initWithEffect:PGGlassEffect()];
    }
    glass.userInteractionEnabled = NO;
    PGMarkOwned(glass);
    // A pane goes in at index 0, but a host that rebuilds its content puts that in at index 0 too
    // and the pane would end up over it. Depth keeps a pane behind whatever the host draws.
    glass.layer.zPosition = -1;
    return glass;
}

UIView *PGGlassFor(UIView *host, const void *key) {
    UIView *glass = objc_getAssociatedObject(host, key);
    if (!glass) {
        glass = newPane();
        objc_setAssociatedObject(host, key, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != host) [host insertSubview:glass atIndex:0];
    return glass;
}

static char kPanesKey;

UIView *PGGlassAt(UIView *host, NSUInteger index) {
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

void PGHideGlassFrom(UIView *host, NSUInteger count) {
    NSArray<UIView *> *panes = objc_getAssociatedObject(host, &kPanesKey);
    for (NSUInteger i = count; i < panes.count; i++) panes[i].hidden = YES;
}

void PGShapeGlass(UIView *glass, CGFloat radius, BOOL capsule) {
    if ([glass isKindOfClass:PGLegacyGlassView.class]) {
        PGLegacyGlassView *legacy = (PGLegacyGlassView *)glass;
        legacy.cornerRadius = radius;
        legacy.capsule = capsule;
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
