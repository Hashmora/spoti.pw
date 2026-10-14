// Your Updates, from the left menu: the redesign's bar over the list (Pages/PageBar.m).
//
// Tree (trees/continuous/8.txt): NotificationCenterView holds the list, a UICollectionView the size of the screen
// on #000000, and over it the navigation controller's blur (8.txt:194), SPNavigationBar with Back, the title
// "Your Updates" and the Encore ⋯ of the page's own (8.txt:204). The list already runs under the bar, so only the
// bar changes: no blur, the title on a glass capsule, Back and ⋯ glass circles. The ⋯ is the one in this page's
// bar, which is what it fires; the player's has nothing to do with it.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

%group SGRYourUpdates
%hook SGRNotificationCenter
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
    __weak UIViewController *weak = (UIViewController *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weak) SGRDressBarPage(weak);
    });
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
    Class page = SGRPageClass(@"YourUpdates_CommonImpl", @"NotificationCenterViewController");
    if (page) {
        %init(SGRYourUpdates, SGRNotificationCenter = page);
    } else {
        SGLog(@"class YourUpdates_CommonImpl.NotificationCenterViewController not found, Your Updates keeps Spotify's bar");
    }
}
