// Redesign, iOS < 26: the popup the AI playlist's ⋯ opens (Report a problem, Clear conversation) as the queue's glass.
//
// AIPlaylist_PlaylistCreationPageImpl.PlaylistCreationMoreOptionsViewController, presented by the page's own
// BottomSheetPresentationController, not by Navigation's sheet (trees/continuous/3.txt:1634-1667, 1706): in a UITransitionView of the
// window, a 60% black dim, the controller's view (PlaylistCreationMoreOptionsView, 390 x 174 at the foot, #1F1F1F r=16) and, beside
// it, a 28pt strip with the grabber that lies over the card's top. So the sheet pass of SGRSheetPopups.x never met it. The
// controller's view is the card itself and gets the queue's pane and the screen's top corners (SGRGlassSheetView), as the
// podcast speed popup's card does; the grabber stays Spotify's, over the glass. Its two rows have no paint of their own.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Pages/Pages.h"

static NSString *const kCardSuffix = @"PlaylistCreationMoreOptionsView";

static void moreChrome(UIViewController *controller) {
    UIView *card = controller.viewIfLoaded;
    if (!card || card.bounds.size.width < 1) return;
    if (![NSStringFromClass(card.class) hasSuffix:kCardSuffix]) return;
    if (card.layer.mask) card.layer.mask = nil;
    SGRGlassSheetView(card);
}

// The rows are built after the first layout, and the grey comes back with them.
static void passes(UIViewController *controller) {
    __weak UIViewController *weak = controller;
    moreChrome(controller);
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) moreChrome(weak);
        });
    }
}

%group SGRAIPlaylistMore
%hook SGRMoreOptionsController
- (void)viewDidLayoutSubviews {
    %orig;
    moreChrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    moreChrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    passes((UIViewController *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class more = SGRPageClass(@"AIPlaylist_PlaylistCreationPageImpl", @"PlaylistCreationMoreOptionsViewController");
    if (more) {
        %init(SGRAIPlaylistMore, SGRMoreOptionsController = more);
    } else {
        SGLog(@"class AIPlaylist_PlaylistCreationPageImpl.PlaylistCreationMoreOptionsViewController not found, the AI playlist's ⋯ popup keeps Spotify's grey");
    }
}
