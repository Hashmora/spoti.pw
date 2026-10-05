// Artist redesign: glass for the artist attribution sheet (the "Michael Jackson, Artist / Thriller, Album"
// credits list that rises from the now playing ⋯). It is the same Navigation sheet the queue and the Connect
// picker are (id=sheet-view), but nothing gave it a pane: the dump shows it as the opaque #1F1F1F Spotify
// paints, with no glass under it. Hosted by Artist_ArtistAttributionPageImpl's bottom sheet controller.
// PGRGlassSheetChrome puts the pane behind the sheet's paint (the same heavy blur, dark body and rim as the
// queue's) and clears the grey of the wrappers and rows.
#import "Core/PGCore.h"
#import "Redesigned/Kit/PGRKit.h"

static NSString *const kSheetController = @"_TtC32Artist_ArtistAttributionPageImpl42ArtistAttributionBottomSheetViewController";

static void chrome(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (root) PGRGlassSheetChrome(root);
}

%hook _TtC32Artist_ArtistAttributionPageImpl42ArtistAttributionBottomSheetViewController
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
    if (!PGRedesignedUI()) return;
    %init;
    PGRequireClasses(@[kSheetController]);
}
