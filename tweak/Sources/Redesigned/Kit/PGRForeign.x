// See PGRForeign.h: this tweak's views are the only ones drawn on its pages while Glass UI is on.
#import <dlfcn.h>
#import <objc/runtime.h>
#import "Core/PGCore.h"
#import "PGRForeign.h"

static NSString *const kPlayerScreenIdentifier = @"SPTNowPlayingViewContainerViewController";

#pragma mark - who is calling

// The image the other tweak's classes come from, read off one of them. Found on first use, which is a layout
// pass: every injected image is loaded long before that. NULL when the other tweak is not in the IPA, and
// then nothing here ever takes anything.
static const char *foreignImage(void) {
    static const char *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *name in @[@"SGRHeaderInfo", @"SGRMirrorButton", @"SGRArtworkField", @"SGRPlayCapsule", @"SGRTabBarHost"]) {
            Class cls = NSClassFromString(name);
            const char *image = cls ? class_getImageName(cls) : NULL;
            if (!image || strstr(image, "pureglass")) continue;
            path = strdup(image);
            PGLog(@"foreign: the other tweak's views come from %s", path);
            break;
        }
    });
    return path;
}

BOOL PGRForeignTweakPresent(void) {
    return foreignImage() != NULL;
}

BOOL PGRCalledFromForeign(void *returnAddress) {
    const char *foreign = foreignImage();
    if (!foreign || !returnAddress) return NO;
    Dl_info info;
    if (!dladdr(returnAddress, &info) || !info.dli_fname) return NO;
    return strcmp(info.dli_fname, foreign) == 0;
}

@implementation PGRSteadyLayer
- (void)setHidden:(BOOL)hidden {
    if (hidden && PGRCalledFromForeign(__builtin_return_address(0))) return;
    [super setHidden:hidden];
}
- (void)setMask:(CALayer *)mask {
    if (mask && PGRCalledFromForeign(__builtin_return_address(0))) return;
    [super setMask:mask];
}
@end

#pragma mark - taking the other tweak's views

static BOOL hasForeignPrefix(const char *name) {
    return name[0] == 'S' && name[1] == 'G' && name[2] == 'R';
}

BOOL PGRIsForeignOverlay(UIView *view) {
    Class cls = object_getClass(view);
    const char *raw = class_getName(cls);
    if (!hasForeignPrefix(raw)) return NO;

    static NSMapTable<Class, NSNumber *> *verdicts;
    if (!verdicts) verdicts = [NSMapTable strongToStrongObjectsMapTable];
    NSNumber *known = [verdicts objectForKey:cls];
    if (known) return known.boolValue;

    NSString *name = @(raw);
    BOOL take = NO;
    // SGRImageObserved_UIImageView, SGRLayoutObserved_UIView, SGRSuppressed_UILabel: Spotify's own views
    // under a subclass made at run time, which Spotify lays out and this tweak needs. They also have no image.
    if (![name containsString:@"Observed_"] && ![name containsString:@"Suppressed_"]) {
        const char *image = class_getImageName(cls);
        if (image && !strstr(image, "pureglass")) {
            take = NSClassFromString([@"PGR" stringByAppendingString:[name substringFromIndex:3]]) != nil;
        }
    }
    [verdicts setObject:@(take) forKey:cls];
    return take;
}

void PGRConcealForeign(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;

    static NSMutableSet<NSString *> *told;
    if (!told) told = [NSMutableSet set];
    NSString *name = NSStringFromClass(object_getClass(view));
    if ([told containsObject:name]) return;
    [told addObject:name];
    PGLog(@"foreign: concealed %@ %@ in %@", name, NSStringFromCGRect(view.frame), NSStringFromClass(view.superview.class));
}

static BOOL inPlayerScreen(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kPlayerScreenIdentifier]) return YES;
    }
    return NO;
}

#pragma mark - panes over panes

static BOOL covers(CGRect a, CGRect b) {
    CGRect hit = CGRectIntersection(a, b);
    if (CGRectIsNull(hit)) return NO;
    CGFloat smaller = MIN(a.size.width * a.size.height, b.size.width * b.size.height);
    return smaller >= 1 && hit.size.width * hit.size.height >= smaller * 0.6;
}

void PGREvictTwinPanes(UIView *pane) {
    UIView *host = pane.superview;
    if (!host || pane.hidden || pane.bounds.size.width < 1) return;
    for (UIView *sibling in host.subviews) {
        if (sibling == pane || object_getClass(sibling) != UIVisualEffectView.class || PGIsOwned(sibling)) continue;
        if (covers(pane.frame, sibling.frame)) PGRConcealForeign(sibling);
    }
}

// A pane of the other tweak's that comes in beside a pane of this one. It is looked at a turn of the run loop
// later, when its owner has given it its frame (it is added first and sized after).
static void evictIfTwin(UIView *effect) {
    __weak UIView *weak = effect;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *pane = weak;
        UIView *host = pane.superview;
        if (!pane || !host || PGIsOwned(pane) || !pane.window) return;
        for (UIView *sibling in host.subviews) {
            if (object_getClass(sibling) != PGLegacyGlassView.class || sibling.hidden) continue;
            if (covers(sibling.frame, pane.frame)) {
                PGRConcealForeign(pane);
                return;
            }
        }
    });
}

%hook UIView
- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    if (!view.window) return;
    Class cls = object_getClass(view);
    if (hasForeignPrefix(class_getName(cls))) {
        if (PGRIsForeignOverlay(view) && !inPlayerScreen(view)) PGRConcealForeign(view);
    } else if (cls == UIVisualEffectView.class && !PGIsOwned(view)) {
        evictIfTwin(view);
    }
}
%end

%ctor {
    if (!PGRedesignedUI()) return;
    %init;
}
