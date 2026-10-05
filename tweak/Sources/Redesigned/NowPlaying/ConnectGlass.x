// Now playing redesign: glass for the Connect device picker. Its sheet is the same Navigation sheet the queue
// and the ⋯ menu are (id=sheet-view, trees/continuous 2026-10-05), but nothing gave it a pane: the pane stayed
// the opaque #1F1F1F Spotify paints it, so the picker was the one sheet with no glass at all. Content is
// SwiftUI (Connect_DevicePickerUIImpl.DevicePickerViewController hosts it), whose own cards -- the playing
// device's, the Connect button -- are left as they are (SGRIsSheetCard). The grey fade over the bottom of the
// list, above the Connect button, is switched off (clearFade).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

// The thin grey fade SwiftUI lays over the bottom of the device list, right above the Connect button
// (trees 2026-10-05: a full-width _UIShapeHitTestingView, 42 pt tall, ending at the button's top edge, with
// no fill of its own -- a gradient is not a background colour, so the dump shows none). On the glass it reads
// as a grey band. SwiftUI's shape views paint their own fills (the grabber, the cards), so this one is told
// apart by size: full width, short, no colour. Its layer is switched off rather than its alpha, since alpha
// under 0.01 would also take it out of hit testing.
static NSString *const kShapeViewSuffix = @"UIShapeHitTestingView";

static void clearFade(UIView *sheet) {
    CGFloat width = sheet.bounds.size.width;
    if (width < 1) return;
    SGForEachView(sheet, ^(UIView *view) {
        if (![NSStringFromClass(view.class) hasSuffix:kShapeViewSuffix]) return;
        CGRect frame = view.frame;
        if (frame.size.width < width * 0.9 || frame.size.height < 8 || frame.size.height > 80) return;
        if (view.subviews.count || SGIsVisibleColor(view.layer.backgroundColor)) return;
        if (view.layer.opacity != 0) {
            view.layer.opacity = 0;
            SGLog(@"redesign connect: cleared the fade above the button, %@", NSStringFromCGRect(frame));
        }
    });
}

static void chrome(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (!root) return;
    UIView *glass = SGRGlassSheetChrome(root);
    if (glass) clearFade(glass.superview);
}

%hook _TtC26Connect_DevicePickerUIImpl26DevicePickerViewController
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
