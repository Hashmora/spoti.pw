// Spotify's in-app browser (SPTWebViewControllerImplementation, opened from Settings > About and from links in the app),
// the redesign's buttons on glass.
//
// Tree (trees/continuous/19.txt): a form sheet holding a navigation controller of its own, with SPNavigationBar 390x56
// over the page and Spotify's blur (#1C1C1C@0.73) behind it. The bar's content view holds a stack at the leading edge
// with the close button, a stack at the trailing edge with one more, and the title control: the page's title and its host
// in two labels between Back and Forward (id=webviewcontroller-backbutton, -forwardbutton), two 24x24 buttons that are the
// title control's own, not the bar's. Every one of them is a bare glyph.
//
// Each gets a glass circle behind its glyph, a child of the control that draws it (SGRGlassInside), so the circle goes
// where the control goes, takes its alpha (Back and Forward dim when there is nowhere to go) and answers its press.
// The bar, its blur and its title stay Spotify's: only the buttons change.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kBarGlassKey, kWebGlassKey, kBackKey, kForwardKey, kWatchedKey;

// Behind Back and Forward, which stand 24pt apart from the title's text at the edges of the title control.
static const CGFloat kWebGlass = 32;

static UIView *subviewNamed(UIView *host, NSString *name) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:name]) return sub;
    }
    return nil;
}

// The glass reaches past a 24pt button, so nothing between it and the bar may clip it.
static void unclip(UIView *view) {
    for (UIView *v = view; v && ![v isKindOfClass:UINavigationBar.class]; v = v.superview) {
        if (v.clipsToBounds) v.clipsToBounds = NO;
    }
}

// An item of the bar (a _UIButtonBarButton): the circle goes into the button its glyph is drawn by, so it is
// concentric with the glyph whatever the item's own width.
static void glassItem(UIView *item) {
    UIView *button = subviewNamed(item, @"_UIModernBarButton");
    if (!button || button.bounds.size.width < 1) return;
    unclip(button);
    SGRGlassInside(button, &kBarGlassKey, SGRGlassCircleSize);
}

static void glassWebButton(UIView *button) {
    if (!button || button.bounds.size.width < 1) return;
    unclip(button);
    SGRGlassInside(button, &kWebGlassKey, kWebGlass);
}

static void dressTitleButtons(UIView *title) {
    glassWebButton(SGRFindByIdentifier(title, @"webviewcontroller-backbutton", &kBackKey));
    glassWebButton(SGRFindByIdentifier(title, @"webviewcontroller-forwardbutton", &kForwardKey));
}

static void dress(UIViewController *page) {
    UINavigationController *navigation = page.navigationController;
    if (!page.viewIfLoaded.window || !navigation) return;
    UIView *content = nil;
    for (UIView *sub in navigation.navigationBar.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"_UINavigationBarContentView"]) content = sub;
    }
    if (!content) return;
    for (UIView *sub in content.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if ([name isEqualToString:@"_UIButtonBarButton"]) {
            glassItem(sub);
        } else if ([name isEqualToString:@"_UIButtonBarStackView"]) {
            for (UIView *item in sub.subviews) {
                if ([NSStringFromClass(item.class) isEqualToString:@"_UIButtonBarButton"]) glassItem(item);
            }
        }
    }
    UIView *title = subviewNamed(content, @"_UINavigationBarTitleControl");
    if (!title) return;
    dressTitleButtons(title);
    // The title is laid out again as the page's name and host arrive: the one pass that reaches Back and Forward after the page's own.
    if (!objc_getAssociatedObject(title, &kWatchedKey) && SGRObserveLayout(title, ^(UIView *view) { dressTitleButtons(view); })) {
        objc_setAssociatedObject(title, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%group SGRWebBrowser
%hook SGRBrowserController
- (void)viewDidLayoutSubviews {
    %orig;
    dress((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // The bar's buttons are made after the first layout.
    SGRRepeatPass((UIViewController *)self, @[@0.0, @0.25, @0.6], ^(UIViewController *c) { dress(c); });
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class page = NSClassFromString(@"SPTWebViewControllerImplementation");
    if (page) {
        %init(SGRWebBrowser, SGRBrowserController = page);
    } else {
        SGLog(@"class SPTWebViewControllerImplementation not found, the in-app browser keeps its flat buttons");
    }
}
