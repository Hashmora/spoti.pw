// An artist's concerts (LiveEvents_ArtistLiveEventsPageImpl.ArtistLiveEventsPageViewController, from the artist popup):
// the redesign's bar over the list, as Recents has it (Pages/PageBar.m).
//
// Tree (trees/continuous/42.txt): the list (ArtistLiveEventsPage.ContentScrollView) is the size of the screen on
// #000000, so it already runs under the bar; over it the navigation controller's blur (390x91, #1C1C1C@0.73) and
// SPNavigationBar with Back, the artist's name as a label and a trailing Share. So the blur goes, the name sits white
// on a glass capsule, Back and Share are glass circles pinned to the corners.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

%group SGRArtistConcerts
%hook SGRConcertsController
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
    // The bar's buttons and title are made after the first layout.
    __weak UIViewController *weak = (UIViewController *)self;
    for (NSNumber *delay in @[@0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) SGRDressBarPage(weak);
        });
    }
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
    Class page = SGRPageClass(@"LiveEvents_ArtistLiveEventsPageImpl", @"ArtistLiveEventsPageViewController");
    if (page) {
        // The page is hosted by a controller of Spotify's page template, which is the top of the stack.
        SGRRegisterBarPages(^BOOL(UIViewController *top) { return SGRPageIsOrHolds(top, page); });
        %init(SGRArtistConcerts, SGRConcertsController = page);
    } else {
        SGLog(@"class LiveEvents_ArtistLiveEventsPageImpl.ArtistLiveEventsPageViewController not found, the artist's concerts page keeps Spotify's bar");
    }
}
