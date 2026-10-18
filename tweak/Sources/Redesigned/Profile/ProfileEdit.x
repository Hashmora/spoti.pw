// Profile, iOS < 26: the Edit profile sheet on glass, as the Edit playlist sheet is (Playlist/PlaylistEdit.x).
//
// Tree (trees/continuous/6.txt:685-728): a page sheet whose pane is the black view of Tome_PageTemplateImpl's loader
// (the navigation controller's superview), holding a UINavigationController with
// Profile_CommonImpl.EditProfileViewController: EditProfileView (#000000) with the photo, the Name row and a 1pt rule,
// under a 56pt UINavigationBar that Spotify backs with a black _UIBarBackground. The bar holds Cancel (a
// _UIButtonBarButton at the leading edge), Save (the trailing one, #37F200@0.30 while there is nothing to save) and the
// title "Edit Profile" in a _UINavigationBarTitleControl, all plain text.
//
//  - The pane gets the queue's glass and the screen's top corners (SGRGlassSheetView), darkened a little the way the Edit
//    playlist sheet is, and the black of the navigation view and the page goes with it.
//  - The bar's black backing goes (alpha, never hidden), and the bar is moved down 10pt: with the screen's corner radius
//    on the pane the Cancel and Save at 8pt from the edge, 6pt from the top, would be cut.
//  - Cancel, Save and the title are on glass capsules, wider than their labels, as the other pages' titles are. They
//    reach past their controls, so the views between them and the bar stop clipping.
// UIKit builds the bar's buttons and its title control again whenever the item changes, after the bar's own pass, so the
// content view's pass is watched too (as PlaylistEdit.x does for its pill).
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Pages/Pages.h"

static const CGFloat kEditShift = 10;
// How much black the pane's glass carries over its body: the Edit playlist sheet's.
static const CGFloat kEditDim = 0.4;
// Side padding of a capsule beside its label, and its height (the title's are the other pages': Pages/PageBar.m).
static const CGFloat kButtonPadding = 12, kButtonHeight = 36, kTitlePadding = 18, kTitleHeight = 44;

static char kButtonGlassKey, kTitleGlassKey;

static __weak UINavigationController *sg_profileNavigation;

static UIView *subviewNamed(UIView *host, NSString *name) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:name]) return sub;
    }
    return nil;
}

static UILabel *labelIn(UIView *root) {
    __block UILabel *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) found = (UILabel *)v;
    });
    return found;
}

// The views between `view` and the bar stop clipping: the capsule is a subview that reaches past its control.
static void unclip(UIView *view, UIView *bar) {
    for (UIView *v = view; v && v != bar; v = v.superview) {
        if (v.clipsToBounds) v.clipsToBounds = NO;
    }
}

static void glassCapsule(UIView *control, UILabel *label, const void *key, CGFloat padding, CGFloat height, UIView *bar) {
    if (!control || !label) return;
    CGFloat content = ceil([label sizeThatFits:CGSizeMake(CGFLOAT_MAX, height)].width);
    if (content < 1) return;
    unclip(control, bar);
    SGRGlassCapsuleInside(control, key, CGSizeMake(content + 2 * padding, height), NO);
}

static void dressBar(UINavigationController *navigation) {
    UINavigationBar *bar = navigation.navigationBar;
    UIView *content = subviewNamed(bar, @"_UINavigationBarContentView");
    if (!content) return;
    if (bar.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // Spotify's black behind the bar.
    UIView *backing = subviewNamed(bar, @"_UIBarBackground");
    if (backing && backing.alpha != 0) backing.alpha = 0;

    CGAffineTransform shift = CGAffineTransformMakeTranslation(0, kEditShift);
    if (!CGAffineTransformEqualToTransform(content.transform, shift)) content.transform = shift;

    // Cancel and Save: a _UIButtonBarButton in each _UIButtonBarStackView, the label in its _UIModernBarButton.
    for (UIView *stack in content.subviews) {
        if (![NSStringFromClass(stack.class) isEqualToString:@"_UIButtonBarStackView"]) continue;
        for (UIView *item in stack.subviews) {
            UIView *button = subviewNamed(item, @"_UIModernBarButton") ?: item;
            glassCapsule(button, labelIn(button), &kButtonGlassKey, kButtonPadding, kButtonHeight, bar);
        }
    }

    UIView *title = subviewNamed(content, @"_UINavigationBarTitleControl");
    if (title) glassCapsule(title, labelIn(title), &kTitleGlassKey, kTitlePadding, kTitleHeight, bar);
}

static void chrome(UIViewController *controller) {
    UINavigationController *navigation = controller.navigationController;
    UIView *pane = navigation.view.superview;
    if (!navigation || !pane || pane.bounds.size.width < 300) return;
    // A sheet is a card with a gap above it, never as tall as the screen.
    if (pane.bounds.size.height >= UIScreen.mainScreen.bounds.size.height - 1) return;
    if (sg_profileNavigation != navigation) {
        sg_profileNavigation = navigation;
        SGLog(@"redesign profile: Edit profile sheet on glass");
    }
    if (pane.layer.mask) pane.layer.mask = nil;
    UIView *glass = SGRGlassSheetView(pane);
    if (glass && !SGRReduceTransparency()) SGRDimSheetGlass(glass, kEditDim);
    UIEdgeInsets extra = controller.additionalSafeAreaInsets;
    if (extra.top != kEditShift) {
        extra.top = kEditShift;
        controller.additionalSafeAreaInsets = extra;
    }
    dressBar(navigation);
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

%group SGREditProfile
%hook SGREditProfileController
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

// The bar lays its buttons and title out again as the item changes (Save is lit once there is something to save).
%group SGREditProfileBar
%hook _UINavigationBarContentView
- (void)layoutSubviews {
    %orig;
    UIView *bar = ((UIView *)self).superview;
    UINavigationController *navigation = sg_profileNavigation;
    if (!navigation || bar != navigation.navigationBar) return;
    dressBar(navigation);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class edit = SGRPageClass(@"Profile_CommonImpl", @"EditProfileViewController");
    if (!edit) {
        SGLog(@"class Profile_CommonImpl.EditProfileViewController not found, the Edit profile sheet keeps Spotify's black");
        return;
    }
    %init(SGREditProfile, SGREditProfileController = edit);
    if (NSClassFromString(@"_UINavigationBarContentView")) %init(SGREditProfileBar);
}
