// Now playing redesign: glass for the Connect device picker. Its sheet is the same Navigation sheet the queue
// and the ⋯ menu are (id=sheet-view, trees/continuous 2026-10-05), but nothing gave it a pane: the pane stayed
// the opaque #1F1F1F Spotify paints it, so the picker was the one sheet with no glass at all. Content is
// SwiftUI (Connect_DevicePickerUIImpl.DevicePickerViewController hosts it), whose own cards -- the playing
// device's, the Connect button -- are left as they are (SGRIsSheetCard).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static void chrome(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (root) SGRGlassSheetChrome(root);
}

%hook _TtC26Connect_DevicePickerUIImpl26DevicePickerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC26Connect_DevicePickerUIImpl26DevicePickerViewController"]);
}
