// Podcast redesign, iOS < 26: the Chapters page (Show all in an episode's Chapters section). Unlike the
// album's page it is a plain list under UIKit's navigation bar (trees/continuous/18.txt):
// EntitySegments_EntitySegmentsPageImpl.EntitySegmentsViewController, with SPNavigationBar's
// _UIButtonBarButton for Back and _UINavigationBarTitleControl for the title, and beside the bar, in the
// navigation controller's own view, Spotify's dark backing: a plain UIView > UIVisualEffectView
// (#1C1C1C@0.73), 91pt.
//
// While the page is up the backing is masked out (an empty mask, since Spotify animates its alpha), Back
// gets a glass circle and the title a glass capsule, as every redesigned page has them. All of it comes off
// again as the page goes, since the navigation bar and its buttons are the next page's.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static char kBackKey, kTitleKey, kMaskKey;
static const CGFloat kCapsuleHeight = 44, kCapsulePadding = 18;

static UIView *firstOfClass(UIView *root, NSString *suffix, int depth) {
    if (!root || depth > 6) return nil;
    if ([NSStringFromClass(root.class) hasSuffix:suffix]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = firstOfClass(sub, suffix, depth + 1);
        if (found) return found;
    }
    return nil;
}

static UILabel *labelIn(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return (UILabel *)view;
    for (UIView *sub in view.subviews) {
        UILabel *label = labelIn(sub);
        if (label) return label;
    }
    return nil;
}

// Spotify's backing of the bar: the one plain UIView of the navigation controller's view that holds a blur.
static UIView *backingOf(UINavigationController *nav) {
    for (UIView *sub in nav.view.subviews) {
        if (object_getClass(sub) != UIView.class || sub.subviews.count != 1) continue;
        if ([sub.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) return sub;
    }
    return nil;
}

static void dress(UIViewController *page) {
    UINavigationController *nav = page.navigationController;
    if (!nav || !page.viewIfLoaded.window) return;
    UIView *backing = backingOf(nav);
    if (backing && !backing.layer.mask) {
        backing.layer.mask = [CALayer layer];
        objc_setAssociatedObject(page, &kMaskKey, backing, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *bar = nav.navigationBar;
    UIView *back = firstOfClass(bar, @"_UIButtonBarButton", 0);
    if (back && back.bounds.size.width > 1) SGRGlassInside(back, &kBackKey, kCapsuleHeight);
    UIView *title = firstOfClass(bar, @"_UINavigationBarTitleControl", 0);
    UILabel *text = title ? labelIn(title) : nil;
    if (title && text.text.length) {
        CGFloat wanted = ceil([text sizeThatFits:CGSizeMake(CGFLOAT_MAX, kCapsuleHeight)].width) + 2 * kCapsulePadding;
        SGRGlassCapsuleInside(title, &kTitleKey, CGSizeMake(MAX(wanted, kCapsuleHeight), kCapsuleHeight), NO);
    }
}

static void undress(UIViewController *page) {
    UIView *backing = objc_getAssociatedObject(page, &kMaskKey);
    backing.layer.mask = nil;
    objc_setAssociatedObject(page, &kMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *bar = page.navigationController.navigationBar;
    UIView *back = firstOfClass(bar, @"_UIButtonBarButton", 0);
    UIView *title = firstOfClass(bar, @"_UINavigationBarTitleControl", 0);
    for (NSValue *pair in @[[NSValue valueWithPointer:&kBackKey], [NSValue valueWithPointer:&kTitleKey]]) {
        const void *key = pair.pointerValue;
        UIView *owner = key == &kBackKey ? back : title;
        UIView *glass = objc_getAssociatedObject(owner, key);
        [glass removeFromSuperview];
        objc_setAssociatedObject(owner, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook _TtC37EntitySegments_EntitySegmentsPageImpl28EntitySegmentsViewController
- (void)viewDidLayoutSubviews {
    %orig;
    dress((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dress((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) dress(weak);
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    undress((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"_TtC37EntitySegments_EntitySegmentsPageImpl28EntitySegmentsViewController"]);
}
