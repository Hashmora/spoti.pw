// Import your music (TheStage_VtecImpl.VtecContainerController): the redesign's bar over the page (Pages/PageBar.m),
// Spotify's header gone and Back a glass circle.
//
// Tree (trees/continuous/24.txt): the page is a web page, a VtecContainerView on #000000 whose WKWebView starts under the
// bar ({0, 91}, :24), and over it the navigation controller's blur (390x91, #1C1C1C@0.73, :46) and SPNavigationBar with
// Back and no title (:50). The page sits in a navigation controller of its own, a VtecNavigationController
// (:420-421) inside the page template's LoadableTemplateViewController, so its own `navigationController` is that one,
// which draws no bar. The bar to dress is the main stack's, the one the template's controller is in: that controller
// is what is handed to PageBar.m, which takes the bar from it and tests it against the top of the stack.
//
// A Vtec page of another window (Create cover art's Save popup, Kit/CoverArt) has no such stack around it and is left alone.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static Class sg_vtecNavigation;

// The controller of the main stack's page that holds this Vtec page: the one the Vtec navigation controller is a child of.
static UIViewController *outerOf(UIViewController *container) {
    for (UIViewController *vc = container.parentViewController; vc; vc = vc.parentViewController) {
        if (sg_vtecNavigation && [vc isKindOfClass:sg_vtecNavigation]) return vc.parentViewController;
    }
    return nil;
}

%group SGRImportMusic
%hook SGRVtecContainer
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIViewController *outer = outerOf((UIViewController *)self);
    if (outer) SGRDressBarPage(outer);
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *outer = outerOf((UIViewController *)self);
    if (outer) SGRDressBarPage(outer);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // The bar's buttons are made after the first layout.
    SGRRepeatPass((UIViewController *)self, @[@0.25, @0.6], ^(UIViewController *c) {
        UIViewController *outer = outerOf(c);
        if (outer) SGRDressBarPage(outer);
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    UIViewController *outer = outerOf((UIViewController *)self);
    if (outer) SGRUndressBarPage(outer);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class page = SGRSwiftClass(@"TheStage_VtecImpl", @"VtecContainerController");
    sg_vtecNavigation = SGRSwiftClass(@"TheStage_VtecImpl", @"VtecNavigationController");
    if (page && sg_vtecNavigation) {
        // The page is hosted by a controller of Spotify's page template, which is the top of the stack.
        SGRRegisterBarPages(^BOOL(UIViewController *top) { return SGRPageIsOrHolds(top, page); });
        %init(SGRImportMusic, SGRVtecContainer = page);
    } else {
        SGLog(@"class TheStage_VtecImpl.VtecContainerController or VtecNavigationController not found, Import your music keeps Spotify's bar");
    }
}
