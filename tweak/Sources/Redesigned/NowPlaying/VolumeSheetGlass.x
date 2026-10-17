// Now playing redesign: glass for the Connect volume sheet (the device's name, its volume slider with the minus and
// plus buttons and the previous / play / next row, which rises from the Connect device's volume control). It is
// the same Navigation sheet the queue, the sleep timer and the Connect picker are (NavigationUI_SheetAPI's
// SheetPresenter, id=sheet-view, #1F1F1F), hosted by Connect_VolumeUXImpl's bottom sheet controller, and nothing gave it a pane.
// SGRGlassSheetChrome puts the pane behind the sheet's paint (the same heavy blur, dark body and rim as the
// queue's) and clears the grey of the wrappers.
//
// Spotify 9.1.78 raises the sheet for another device (Listening on Andrew's MacBook Air) with a SwiftUI hosting
// controller of Connect_VolumeUXImpl's BottomSheetElement and no BottomSheetViewController (trees/continuous/4.txt), so
// the hook below does not run for it: Kit/SGRSheetPopups.x gives that sheet its pane by the name of the hosted
// controller ("Connect_VolumeUXImpl" in its content markers). The hook stays for a build that does present the class.
//
// The sheet's controls (VolumeSliderWithButtons / VolumeSliderNoButtons, PlaybackControlsView, the Encore buttons)
// are left as Spotify draws them. If the PaintAudit report of this sheet still lists a fill, it is one of those.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static NSString *const kSheetController = @"_TtC20Connect_VolumeUXImpl25BottomSheetViewController";

static void chrome(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (root) SGRGlassSheetChrome(root);
}

%hook _TtC20Connect_VolumeUXImpl25BottomSheetViewController
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
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the slider rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[kSheetController]);
}
