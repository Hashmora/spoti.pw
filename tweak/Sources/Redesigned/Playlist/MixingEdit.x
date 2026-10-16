// Playlist redesign, iOS < 26: the Mix transition window, the full-screen page of a Smart Reorder transition with its
// manual effects (PlaylistMixing_MixingUIImpl.MixingEditViewController, trees/continuous/6.txt, 7.txt), on glass.
//
// Tree: a black page (id=MixingEditViewController.View) in a navigation controller of its own, under an SPNavigationBar
// that holds the Back arrow in a _UIButtonBarButton at the leading edge and, in a stack at the trailing one, the Beta
// tag and Encore Primary buttons More and Save. Spotify backs the bar twice, with a blur plate (#1C1C1C@0.73) and with
// the bar's own opaque black _UIBarBackground. In the page itself the Play button of the transition is a 48x32 plate
// (#464646, r=12) in the middle of the waveform, and the bar picker and the jog buttons are MixingBorderedButtons
// (#303030, r=12).
//
//  - The bar's two backings go and the page shows through. Back is pinned over the bar as the glass circle every
//    redesigned page has (SGRPinnedBackOf), at the page's corner and level with the bar's buttons. It is pinned in the
//    navigation controller's view, over the bar, since the bar has to stay live for More and Save and would take the
//    touches of a button under it. Spotify's own arrow is concealed and fired by the mirror.
//  - More and Save are glass capsules where they are, Save with the accent over the glass, since its label is black.
//  - The Play button is a glass capsule, brighter than the rest (prominent), around the same glyph in the same place.
//  - The bordered buttons are glass.
// Each is Spotify's own control with its action and its accessibility; the glass is a subview of it
// (Kit/SGRGlass.h), its own fill is cleared and kept clear as Encore paints it again.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static char kPlayGlassKey, kBorderGlassKey, kBarGlassKey, kBarTintKey, kDressedKey;

// The navigation controller of the Mix transition window while it is up: what tells its bar's buttons from the other
// Primary buttons of the app.
static __weak UINavigationController *sg_mixNavigation;

static Class swiftClass(NSString *module, NSString *name) {
    NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@", (unsigned long)module.length, module, (unsigned long)name.length, name];
    return NSClassFromString(mangled) ?: NSClassFromString([NSString stringWithFormat:@"%@.%@", module, name]);
}

// A class of PlaylistMixing_MixingUIImpl whose mangled name carries a private discriminator (P33_...), found from the
// trees' spelling by its ending.
static Class privateClass(NSString *suffix) {
    Class found = nil;
    int count = objc_getClassList(NULL, 0);
    Class *all = (Class *)malloc(sizeof(Class) * count);
    count = objc_getClassList(all, count);
    for (int i = 0; i < count && !found; i++) {
        NSString *name = NSStringFromClass(all[i]);
        if ([name hasPrefix:@"_TtC27PlaylistMixing_MixingUIImpl"] && [name hasSuffix:suffix]) found = all[i];
    }
    free(all);
    return found;
}

#pragma mark - the bar

static UIView *contentOf(UINavigationBar *bar) {
    for (UIView *sub in bar.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"_UINavigationBarContentView"]) return sub;
    }
    return nil;
}

// The Back arrow: the first control of the stack at the leading half of the bar's content view.
static UIView *backIn(UIView *content) {
    for (UIView *stack in content.subviews) {
        if (![NSStringFromClass(stack.class) isEqualToString:@"_UIButtonBarStackView"]) continue;
        if (CGRectGetMidX(stack.frame) >= content.bounds.size.width / 2) continue;
        for (UIView *button in stack.subviews) {
            if (button.bounds.size.width > 1 && button.bounds.size.height > 1) return button;
        }
    }
    return nil;
}

static void dressBar(UIViewController *controller) {
    UINavigationController *navigation = controller.navigationController;
    UIView *root = controller.viewIfLoaded;
    if (!navigation || !root.window) return;
    if (sg_mixNavigation != navigation) sg_mixNavigation = navigation;

    UINavigationBar *bar = navigation.navigationBar;
    // Glass takes the appearance it inherits, light on a phone in light mode.
    if (bar.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    // The bar's own black, and the blur plate beside it in the navigation controller's view: a mask survives Spotify
    // showing either again, which hidden does not.
    for (UIView *sub in bar.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"_UIBarBackground"] && sub.alpha != 0) sub.alpha = 0;
    }
    for (UIView *sub in navigation.view.subviews) {
        if (sub == bar || object_getClass(sub) != UIView.class) continue;
        for (UIView *inner in sub.subviews) {
            if (![inner isKindOfClass:UIVisualEffectView.class]) continue;
            if (!sub.layer.mask) sub.layer.mask = [CALayer layer];
            if (sub.userInteractionEnabled) sub.userInteractionEnabled = NO;
            break;
        }
    }

    UIView *back = backIn(contentOf(bar));
    if (back) SGRPinnedBackOf(navigation.view, back);
}

#pragma mark - controls

// The shape Spotify's own plate is replaced by: its fill cleared, kept clear as it is painted again.
static void clearFill(UIView *control) {
    if (control.backgroundColor && ![control.backgroundColor isEqual:UIColor.clearColor]) control.backgroundColor = UIColor.clearColor;
    if (control.layer.backgroundColor) control.layer.backgroundColor = NULL;
}

static void dressPlay(UIView *button) {
    if (button.bounds.size.width < 1 || button.bounds.size.height < 1) return;
    clearFill(button);
    SGRGlassCapsuleInside(button, &kPlayGlassKey, button.bounds.size, YES);
    // The glass grows under a press and would be cut off at the button's edge.
    if (button.clipsToBounds) button.clipsToBounds = NO;
    objc_setAssociatedObject(button, &kDressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void dressBordered(UIView *button) {
    if (button.bounds.size.width < 1 || button.bounds.size.height < 1) return;
    clearFill(button);
    SGRGlassFlatBox(button, &kBorderGlassKey);
    objc_setAssociatedObject(button, &kDressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL inMixBar(UIView *view) {
    UINavigationBar *bar = sg_mixNavigation.navigationBar;
    if (!bar) return NO;
    for (UIView *v = view.superview; v; v = v.superview) {
        if (v == bar) return YES;
    }
    return NO;
}

// The accent over the glass, under the label: Save is drawn with a black label.
static void tintSave(UIView *button, UIView *glass) {
    UIView *film = objc_getAssociatedObject(button, &kBarTintKey);
    if (!film) {
        film = [UIView new];
        film.userInteractionEnabled = NO;
        film.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(button, &kBarTintKey, film, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSInteger rgb = SGRAccentRGB();
    UIColor *color = [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:0.8];
    if (![film.backgroundColor isEqual:color]) film.backgroundColor = color;
    if (film.superview != button) [button insertSubview:film atIndex:glass ? 1 : 0];
    if (!CGRectEqualToRect(film.frame, button.bounds)) film.frame = button.bounds;
    CGFloat radius = button.bounds.size.height / 2;
    if (film.layer.cornerRadius != radius) film.layer.cornerRadius = radius;
}

// More and Save: the Primary buttons of the bar. Save is the last of the stack they are in (its label is in the
// app's language, so it is not told by its word).
static void dressBarButton(UIView *button) {
    if (button.bounds.size.width < 1 || button.bounds.size.height < 1 || !inMixBar(button)) return;
    clearFill(button);
    UIView *inner = button.subviews.lastObject;
    if (inner && inner != objc_getAssociatedObject(button, &kBarTintKey) && CGSizeEqualToSize(inner.bounds.size, button.bounds.size)
        && inner.layer.backgroundColor && CGColorGetAlpha(inner.layer.backgroundColor) > 0.05) {
        inner.layer.backgroundColor = NULL;
    }
    UIView *glass = SGRGlassFlatBox(button, &kBarGlassKey);
    if (button.superview.subviews.lastObject == button) tintSave(button, glass);
    objc_setAssociatedObject(button, &kDressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIColor *keptClear(UIView *view, UIColor *color) {
    if ([objc_getAssociatedObject(view, &kDressedKey) boolValue] && color && CGColorGetAlpha(color.CGColor) > 0.05) return UIColor.clearColor;
    return color;
}

%group SGRMixEdit
%hook SGRMixController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dressBar((UIViewController *)self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    dressBar((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // The bar's buttons are made after the first layout.
    __weak UIViewController *weak = (UIViewController *)self;
    for (NSNumber *delay in @[@0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) dressBar(weak);
        });
    }
}
%end
%end

%group SGRMixPlay
%hook SGRMixPlayButton
- (void)layoutSubviews {
    %orig;
    dressPlay((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) dressPlay((UIView *)self);
}

- (void)setBackgroundColor:(UIColor *)color {
    %orig(keptClear((UIView *)self, color));
}
%end
%end

%group SGRMixBordered
%hook SGRMixBorderedButton
- (void)layoutSubviews {
    %orig;
    dressBordered((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) dressBordered((UIView *)self);
}

- (void)setBackgroundColor:(UIColor *)color {
    %orig(keptClear((UIView *)self, color));
}
%end
%end

%group SGRMixBarButtons
%hook SGRMixPrimaryButton
- (void)layoutSubviews {
    %orig;
    dressBarButton((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) dressBarButton((UIView *)self);
}

- (void)setBackgroundColor:(UIColor *)color {
    %orig(keptClear((UIView *)self, color));
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class page = swiftClass(@"PlaylistMixing_MixingUIImpl", @"MixingEditViewController");
    if (page) {
        %init(SGRMixEdit, SGRMixController = page);
    } else {
        SGLog(@"class PlaylistMixing_MixingUIImpl.MixingEditViewController not found, the Mix transition window keeps Spotify's bar");
    }
    Class play = swiftClass(@"PlaylistMixing_MixingUIImpl", @"MixingPlayButtonView") ?: privateClass(@"MixingPlayButtonView");
    if (play) {
        %init(SGRMixPlay, SGRMixPlayButton = play);
    } else {
        SGLog(@"class PlaylistMixing_MixingUIImpl MixingPlayButtonView not found, the Mix transition's Play button keeps Spotify's plate");
    }
    Class bordered = swiftClass(@"PlaylistMixing_MixingUIImpl", @"MixingBorderedButton");
    if (bordered) {
        %init(SGRMixBordered, SGRMixBorderedButton = bordered);
    } else {
        SGLog(@"class PlaylistMixing_MixingUIImpl.MixingBorderedButton not found, the Mix transition's buttons keep Spotify's plates");
    }
    Class primary = NSClassFromString(@"_TtCCE16Encore_ButtonKitO16EncoreFoundation6Encore6Button7Primary");
    if (primary) {
        %init(SGRMixBarButtons, SGRMixPrimaryButton = primary);
    } else {
        SGLog(@"class Encore.Button.Primary not found, the Mix transition's More and Save keep Spotify's fills");
    }
}
