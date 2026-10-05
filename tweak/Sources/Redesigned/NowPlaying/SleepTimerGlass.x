// Redesign: glass for the sleep timer sheet (the "Sleep timer" list of 5 minutes ... End of track, opened from
// the Queue's Timer button; trees/continuous 2026-10-05). It is the same Navigation sheet as the queue's, the
// ⋯ menu's and the Connect picker's (NavigationUI_SheetImpl, id=sheet-view, #1F1F1F), with one more #1F1F1F
// view over the whole of it (id=sleep_timer_options) that SGRGlassSheetChrome clears with the rest.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static void chrome(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (root) SGRGlassSheetChrome(root);
}

%hook _TtC30PlaybackControl_SleepTimerImpl21OptionsViewController
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
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
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
    SGRequireClasses(@[@"_TtC30PlaybackControl_SleepTimerImpl21OptionsViewController"]);
}
