// Playlist redesign, iOS < 26: the Edit playlist page sheet on glass, the way the queue and the other sheets are.
//
// Tree (trees/continuous/19.txt:1242-1730, 21.txt, 22.txt, 23.txt): a page sheet whose pane is the black view of
// Tome_PageTemplateImpl's loader (the navigation controller's superview), holding SPNavigationController with
// EditItemsViewController: the list (#1F1F1F) under a 56pt SPNavigationBar (Cancel, the title, Save) that Spotify backs
// with its own blur plate (#1C1C1C@0.73), and a StackedActionToolbarElement along the bottom (ToolbarContainerView,
// #1F1F1F) with Encore Primary buttons: Select and Smart Reorder, then in select mode the exit cross, Move and Remove,
// then Back, To top and To bottom. While tracks are dragged the bar's title holds an undo / redo pill
// (UndoRedoBarElement, #FFFFFF@0.10, 23.txt).
//
//  - The pane gets the queue's glass and the screen's top corners (SGRGlassSheetView), darkened a little (kEditDim) so
//    the bright page under it does not wash out the rows. The grey of the list and of the
//    toolbar goes with it (SGRRepaint.x keeps it clear).
//  - The bar's blur plate goes, and the bar and the list are moved down 10pt: with the screen's corner radius on the
//    pane the Cancel and Save at 8pt from the edge, 6pt from the top, would be cut.
//  - Every button of the toolbar and the undo / redo pill is a glass capsule (SGRGlassFlatBox).
//  - The two Smart Reorder popups (get smoother transitions, you have custom transitions) are Navigation sheets and are
//    glassed by SGRSheetPopups.x (the PlaylistMixing_MessagingImpl marker); their big Primary button (Continue, Keep
//    custom transitions) is glass tinted with the accent here, since its label is black.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRRepaint.h"

static const CGFloat kEditShift = 10;

// How much black the pane's glass carries over its body (SGRDimSheetGlass). The sheet floats over the playlist page,
// whose artwork field is bright, and the plain glass read nearly white with the rows on it hard to make out
// (trees/continuous/2.txt); the same dim the dialogs carry, a little lighter.
static const CGFloat kEditDim = 0.4;

static char kToolbarGlassKey, kPopupGlassKey, kPopupTintKey, kPillKey, kPillGlassKey, kDressedKey;

static Class swiftClass(NSString *module, NSString *name) {
    NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@", (unsigned long)module.length, module, (unsigned long)name.length, name];
    return NSClassFromString(mangled) ?: NSClassFromString([NSString stringWithFormat:@"%@.%@", module, name]);
}

static __weak UINavigationController *sg_editNavigation;

#pragma mark - the pane, the bar and the list

static UIView *barOf(UINavigationController *navigation) {
    return navigation.navigationBar;
}

// Spotify's blur behind the bar: a plain UIView the bar's height holding a UIVisualEffectView, beside the bar in the
// navigation controller's view. Alpha, not hidden.
static void hideBarPlate(UINavigationController *navigation) {
    UIView *bar = barOf(navigation);
    for (UIView *sub in navigation.view.subviews) {
        if (sub == bar || object_getClass(sub) != UIView.class) continue;
        if (sub.bounds.size.height > bar.bounds.size.height + 1 || !sub.subviews.count) continue;
        if (![sub.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) continue;
        if (sub.alpha != 0) sub.alpha = 0;
    }
}

static void moveBar(UINavigationController *navigation) {
    for (UIView *sub in barOf(navigation).subviews) {
        if (![NSStringFromClass(sub.class) isEqualToString:@"_UINavigationBarContentView"]) continue;
        CGAffineTransform shift = CGAffineTransformMakeTranslation(0, kEditShift);
        if (!CGAffineTransformEqualToTransform(sub.transform, shift)) sub.transform = shift;
    }
}

static void glassPill(UIView *root) {
    UIView *pill = SGRFindByIdentifier(root, @"UndoRedoBarElement", &kPillKey);
    if (!pill) return;
    if (pill.layer.backgroundColor) pill.layer.backgroundColor = NULL;
    SGRGlassFlatBox(pill, &kPillGlassKey);
}

static void chrome(UIViewController *controller) {
    UINavigationController *navigation = controller.navigationController;
    UIView *pane = navigation.view.superview;
    if (!navigation || !pane || pane.bounds.size.width < 300) return;
    // A sheet is a card with a gap above it, never as tall as the screen.
    if (pane.bounds.size.height >= UIScreen.mainScreen.bounds.size.height - 1) return;
    if (sg_editNavigation != navigation) sg_editNavigation = navigation;
    if (pane.layer.mask) pane.layer.mask = nil;
    UIView *glass = SGRGlassSheetView(pane);
    if (glass && !SGRReduceTransparency()) SGRDimSheetGlass(glass, kEditDim);
    hideBarPlate(navigation);
    moveBar(navigation);
    UIEdgeInsets extra = controller.additionalSafeAreaInsets;
    if (extra.top != kEditShift) {
        extra.top = kEditShift;
        controller.additionalSafeAreaInsets = extra;
    }
    glassPill(barOf(navigation));
}

static void passes(UIViewController *controller) {
    __weak UIViewController *weak = controller;
    chrome(controller);
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}

%group SGREditPlaylist
%hook SGREditItems
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    passes((UIViewController *)self);
}
%end
%end

// The bar lays its buttons out again as the title changes (the undo / redo pill comes in while tracks are dragged).
%group SGREditBar
%hook _UINavigationBarContentView
- (void)layoutSubviews {
    %orig;
    UIView *bar = ((UIView *)self).superview;
    if (!sg_editNavigation || bar != sg_editNavigation.navigationBar) return;
    hideBarPlate(sg_editNavigation);
    moveBar(sg_editNavigation);
    glassPill(bar);
}
%end
%end

#pragma mark - the buttons

static BOOL inToolbar(UIView *view) {
    int depth = 0;
    for (UIView *v = view.superview; v && depth < 8; v = v.superview, depth++) {
        if ([NSStringFromClass(v.class) hasSuffix:@"ToolbarContainerView"]) return YES;
    }
    return NO;
}

// The accent over the glass, under the label: Continue and Keep are drawn with a black label.
static void tint(UIView *button) {
    UIView *glass = objc_getAssociatedObject(button, &kPopupGlassKey);
    UIView *film = objc_getAssociatedObject(button, &kPopupTintKey);
    if (!film) {
        film = [UIView new];
        film.userInteractionEnabled = NO;
        film.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(button, &kPopupTintKey, film, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSInteger rgb = SGRAccentRGB();
    UIColor *color = [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:0.8];
    if (![film.backgroundColor isEqual:color]) film.backgroundColor = color;
    if (film.superview != button) [button insertSubview:film atIndex:glass ? 1 : 0];
    if (!CGRectEqualToRect(film.frame, button.bounds)) film.frame = button.bounds;
    CGFloat radius = button.bounds.size.height / 2;
    if (film.layer.cornerRadius != radius) film.layer.cornerRadius = radius;
}

// Spotify's own fill of the button, if it draws one: the button's or the first view inside it.
static void clearFill(UIView *button) {
    if (button.layer.backgroundColor) button.layer.backgroundColor = NULL;
    UIView *inner = button.subviews.lastObject;
    if (inner && inner != objc_getAssociatedObject(button, &kPopupTintKey) && CGSizeEqualToSize(inner.bounds.size, button.bounds.size)
        && inner.layer.backgroundColor && CGColorGetAlpha(inner.layer.backgroundColor) > 0.05) {
        inner.layer.backgroundColor = NULL;
    }
}

static void dressButton(UIView *button) {
    if (button.bounds.size.width < 1 || button.bounds.size.height < 1) return;
    if (inToolbar(button)) {
        clearFill(button);
        SGRGlassFlatBox(button, &kToolbarGlassKey);
        objc_setAssociatedObject(button, &kDressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if ([button.accessibilityIdentifier isEqualToString:@"Messaging.PrimaryButton"]) {
        clearFill(button);
        SGRGlassFlatBox(button, &kPopupGlassKey);
        tint(button);
        objc_setAssociatedObject(button, &kDressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%group SGREditButtons
%hook SGRPrimaryButton
- (void)layoutSubviews {
    %orig;
    dressButton((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) dressButton((UIView *)self);
}

// Encore paints the button again as it is pressed or let go; a dressed one stays clear.
- (void)setBackgroundColor:(UIColor *)color {
    UIView *button = (UIView *)self;
    if ([objc_getAssociatedObject(button, &kDressedKey) boolValue] && color && CGColorGetAlpha(color.CGColor) > 0.05) color = UIColor.clearColor;
    %orig(color);
}
%end
%end

// The toolbar's grey comes back with its content, as the queue's bars do.
%group SGREditToolbar
%hook SGRToolbarContainer
- (void)layoutSubviews {
    %orig;
    UIView *bar = (UIView *)self;
    if (SGRIsSheetSurface(bar.layer.backgroundColor)) bar.backgroundColor = UIColor.clearColor;
}

- (void)didMoveToWindow {
    %orig;
    UIView *bar = (UIView *)self;
    if (SGRIsSheetSurface(bar.layer.backgroundColor)) bar.backgroundColor = UIColor.clearColor;
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class edit = swiftClass(@"PlaylistEditing_EditPlaylistImpl", @"EditItemsViewController");
    if (edit) {
        %init(SGREditPlaylist, SGREditItems = edit);
    } else {
        SGLog(@"class PlaylistEditing_EditPlaylistImpl.EditItemsViewController not found, the Edit playlist sheet keeps Spotify's grey");
    }
    if (NSClassFromString(@"_UINavigationBarContentView")) %init(SGREditBar);
    Class primary = NSClassFromString(@"_TtCCE16Encore_ButtonKitO16EncoreFoundation6Encore6Button7Primary");
    if (primary) {
        %init(SGREditButtons, SGRPrimaryButton = primary);
    } else {
        SGLog(@"class Encore.Button.Primary not found, the Edit playlist buttons and the Smart Reorder popups keep Spotify's fills");
    }
    Class toolbar = swiftClass(@"PlaylistEditing_ElementsKit", @"ToolbarContainerView");
    if (!toolbar) {
        // Private discriminator in the mangled name (P33_...): found from the trees' spelling by suffix.
        int count = objc_getClassList(NULL, 0);
        Class *all = (Class *)malloc(sizeof(Class) * count);
        count = objc_getClassList(all, count);
        for (int i = 0; i < count && !toolbar; i++) {
            NSString *name = NSStringFromClass(all[i]);
            if ([name hasPrefix:@"_TtC27PlaylistEditing_ElementsKit"] && [name hasSuffix:@"ToolbarContainerView"]) toolbar = all[i];
        }
        free(all);
    }
    if (toolbar) {
        %init(SGREditToolbar, SGRToolbarContainer = toolbar);
    } else {
        SGLog(@"class PlaylistEditing_ElementsKit ToolbarContainerView not found, the Edit playlist toolbar may keep Spotify's grey");
    }
}
