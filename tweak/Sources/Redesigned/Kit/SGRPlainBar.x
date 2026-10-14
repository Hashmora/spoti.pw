// Redesign, iOS < 26: the pages that sit under UIKit's own navigation bar instead of drawing a header of
// their own -- Chapters (Show all of an episode's Chapters), Listening stats and its Top artists and Top
// songs, a track or an artist opened from them, and Your Premium. Each is a controller hosted by
// Navigation_PageAPIIntegrationImpl.MusicAppPageHostingViewController (trees/continuous/9, 10, 11, 12, 18).
//
// The bar is SPNavigationBar with a clear background; the dark band over the top is Spotify's own backing
// beside it in the navigation controller's view, a plain UIView (#000 or clear) around a UIVisualEffectView
// (#1C1C1C@0.73). While one of these pages is up the backing is masked out (an empty mask, since Spotify
// animates its alpha), Back gets a glass circle, the title a glass capsule and a Share on the right a glass
// circle, as every redesigned page has them. All of it comes off as the page goes: the bar and its buttons
// are the next page's.
//
// And the page itself is made dark. Under the redesign these lists drew a white UICollectionView under
// their white labels until the app was left and entered again (device, 2026-10-14), so every hosted page
// is given the dark appearance, which Spotify has everywhere, and the two Stats lists are cleared of the
// white they were painted.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static char kBackKey, kTitleKey, kShareKey, kOwnersKey;
static const CGFloat kCapsuleHeight = 44, kCapsulePadding = 18;
static NSHashTable<UIViewController *> *sg_dressed;
static CALayer *sg_emptyMask;

// A part of the name of a page's own controller, below the hosting one.
static NSArray<NSString *> *pageMarkers(void) {
    return @[@"EntitySegmentsViewController", @"UserTimelineViewController", @"StatsDetailsViewController",
             @"YourPremiumViewController"];
}

static BOOL isPage(UIViewController *controller, int depth) {
    if (depth > 6) return NO;
    for (UIViewController *child in controller.childViewControllers) {
        NSString *name = NSStringFromClass(child.class);
        for (NSString *marker in pageMarkers()) {
            if ([name containsString:marker]) return YES;
        }
        if (isPage(child, depth + 1)) return YES;
    }
    return NO;
}

static UIView *firstOfClass(UIView *root, NSString *suffix, int depth) {
    if (!root || depth > 6) return nil;
    if ([NSStringFromClass(root.class) hasSuffix:suffix]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = firstOfClass(sub, suffix, depth + 1);
        if (found) return found;
    }
    return nil;
}

static UIView *firstWithIdentifierSuffix(UIView *root, NSString *suffix, int depth) {
    if (!root || depth > 8) return nil;
    if ([root.accessibilityIdentifier hasSuffix:suffix]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = firstWithIdentifierSuffix(sub, suffix, depth + 1);
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

static void own(UIViewController *page, UIView *owner) {
    NSHashTable<UIView *> *owners = objc_getAssociatedObject(page, &kOwnersKey);
    if (!owners) {
        owners = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(page, &kOwnersKey, owners, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [owners addObject:owner];
}

// The white UICollectionView Spotify's Stats lists paint.
static void clearStatsLists(UIView *root) {
    SGForEachView(root, ^(UIView *v) {
        if (![v isKindOfClass:UICollectionView.class]) return;
        if (![v.accessibilityIdentifier hasSuffix:@"ViewController.CollectionView"]) return;
        if (![v.accessibilityIdentifier hasPrefix:@"UserTimeline"] && ![v.accessibilityIdentifier hasPrefix:@"StatsDetails"]) return;
        if (v.backgroundColor && ![v.backgroundColor isEqual:UIColor.clearColor]) v.backgroundColor = UIColor.clearColor;
    });
}

static void dress(UIViewController *page) {
    UIView *root = page.viewIfLoaded;
    if (root.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) root.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if (!isPage(page, 0)) return;
    clearStatsLists(root);
    if (!SGBelowiOS26()) return;
    UINavigationController *nav = page.navigationController;
    if (!nav || !root.window) return;
    if (!sg_dressed) sg_dressed = [NSHashTable weakObjectsHashTable];
    [sg_dressed addObject:page];
    UIView *backing = backingOf(nav);
    if (backing) {
        if (!sg_emptyMask) sg_emptyMask = [CALayer layer];
        if (backing.layer.mask != sg_emptyMask) backing.layer.mask = sg_emptyMask;
    }
    UIView *bar = nav.navigationBar;
    // The bar is the navigation controller's and may still be light: its title was black and its glass white.
    if (bar.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    // The circle goes in the control that draws the chevron (_UIModernBarButton), as the profile lists have it
    // (Profile/ProfileListBar.x): the bar button around it is 44pt wide with the glyph off its middle, so a
    // circle in the button was off the glyph, and after a swipe back that was let go the chevron ended up
    // under it (device, 2026-10-15, 18.txt, 19.txt). The shape stays first among the control's subviews.
    UIView *back = firstOfClass(bar, @"_UIButtonBarButton", 0);
    UIView *backHost = nil;
    for (UIView *sub in back.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"_UIModernBarButton"]) backHost = sub;
    }
    if (backHost && backHost.bounds.size.width > 1) {
        // A circle an earlier build put in the bar button itself is taken off.
        [(UIView *)objc_getAssociatedObject(back, &kBackKey) removeFromSuperview];
        objc_setAssociatedObject(back, &kBackKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *glass = SGRGlassInside(backHost, &kBackKey, kCapsuleHeight);
        if (glass) SGRShowGlass(glass, YES);
        own(page, backHost);
    }
    UIView *title = firstOfClass(bar, @"_UINavigationBarTitleControl", 0);
    UILabel *text = title ? labelIn(title) : nil;
    if (title && text.text.length) {
        CGFloat wanted = ceil([text sizeThatFits:CGSizeMake(CGFLOAT_MAX, kCapsuleHeight)].width) + 2 * kCapsulePadding;
        for (UIView *v = title; v && ![v isKindOfClass:UINavigationBar.class]; v = v.superview) {
            if (v.clipsToBounds) v.clipsToBounds = NO;
        }
        UIView *glass = SGRGlassCapsuleInside(title, &kTitleKey, CGSizeMake(MAX(wanted, kCapsuleHeight), kCapsuleHeight), NO);
        if (glass) SGRShowGlass(glass, YES);
        own(page, title);
    }
    // Share on the right (a track or an artist opened from Listening stats): its element view is 24pt wide,
    // so the circle stands out of it to either side, the way the buttons of the other pages sit.
    UIView *share = firstWithIdentifierSuffix(bar, @"ShareButton", 0);
    UIView *shareHost = share.superview;
    if (shareHost && shareHost.bounds.size.height > 1) {
        SGRGlassInside(shareHost, &kShareKey, kCapsuleHeight);
        own(page, shareHost);
    }
}

static void undress(UIViewController *page) {
    [sg_dressed removeObject:page];
    NSHashTable<UIView *> *owners = objc_getAssociatedObject(page, &kOwnersKey);
    for (UIView *owner in owners.allObjects) {
        for (NSValue *pair in @[[NSValue valueWithPointer:&kBackKey], [NSValue valueWithPointer:&kTitleKey], [NSValue valueWithPointer:&kShareKey]]) {
            const void *key = pair.pointerValue;
            UIView *glass = objc_getAssociatedObject(owner, key);
            [glass removeFromSuperview];
            objc_setAssociatedObject(owner, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    [owners removeAllObjects];
    // The backing is shared: a page pushed over this one has dressed before this one goes.
    if (sg_dressed.count) return;
    UIView *backing = backingOf(page.navigationController);
    if (backing.layer.mask == sg_emptyMask) backing.layer.mask = nil;
}

static Class swiftClass(NSString *module, NSString *name) {
    NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@", (unsigned long)module.length, module, (unsigned long)name.length, name];
    return NSClassFromString(mangled) ?: NSClassFromString([NSString stringWithFormat:@"%@.%@", module, name]);
}

%group SGRPlainBarPages
%hook SGRHostingController
- (void)viewDidLoad {
    %orig;
    UIView *root = ((UIViewController *)self).viewIfLoaded;
    if (root.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) root.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}

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
            if (weak && weak.viewIfLoaded.window) dress(weak);
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    undress((UIViewController *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    Class hosting = swiftClass(@"Navigation_PageAPIIntegrationImpl", @"MusicAppPageHostingViewController");
    if (!hosting) {
        SGLog(@"class Navigation_PageAPIIntegrationImpl.MusicAppPageHostingViewController not found, Chapters, Listening stats and Your Premium keep Spotify's bar");
        return;
    }
    %init(SGRPlainBarPages, SGRHostingController = hosting);
}
