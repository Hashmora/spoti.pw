// Create a Blend (Blend_BlendInvitationImpl.BIViewController): the redesign's bar over the page (Pages/PageBar.m),
// Spotify's header gone and Back a glass circle.
//
// Tree (trees/continuous/25.txt): BIView on #000000 holds a UIScrollView with the face pile, the heading, the text and
// the Invite button ({48, 91}, :20); over it the navigation controller's blur (390x91, #1C1C1C@0.73, :50) and SPNavigationBar
// with Back and no title (:60). The page is a child of a MusicAppPageHostingViewController, the top of the stack
// (:450-451), and the content already sits below the bar, so only the bar changes.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

%group SGRBlendInvite
%hook SGRBlendInvitation
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SGRDressBarPage((UIViewController *)self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    SGRDressBarPage((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // The bar's buttons are made after the first layout.
    SGRRepeatPass((UIViewController *)self, @[@0.25, @0.6], ^(UIViewController *c) { SGRDressBarPage(c); });
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    SGRUndressBarPage((UIViewController *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class page = SGRSwiftClass(@"Blend_BlendInvitationImpl", @"BIViewController");
    if (page) {
        SGRRegisterBarPages(^BOOL(UIViewController *top) { return SGRPageIsOrHolds(top, page); });
        %init(SGRBlendInvite, SGRBlendInvitation = page);
    } else {
        SGLog(@"class Blend_BlendInvitationImpl.BIViewController not found, Create a Blend keeps Spotify's bar");
    }
}
