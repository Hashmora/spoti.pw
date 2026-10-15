// Song DNA's page of the songs two people share (SongDNA_ArtistsDNAPageImpl.BlendViewController, reached from a
// contributor's "view N songs together"): the redesign's bar over it (Pages/PageBar.m).
//
// Tree (trees/continuous/41.txt): a black page holding a radial gradient and the list from y=91, over it the navigation
// controller's blur (a plain 390x91 view with a UIVisualEffectView, #1C1C1C@0.73) and SPNavigationBar with Back, a
// trailing stack of Share (the Song DNA share button) and Close, and a title that is a picture, the Song DNA logo and
// its Beta tag, not a label. So the blur goes, Back, Share and Close are glass circles pinned to the corners (Close at
// the corner, Share beside it), and the logo sits on a glass capsule the way a name does on the playlist.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

%group SGRSongDNABlend
%hook SGRBlendController
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
    Class page = SGRPageClass(@"SongDNA_ArtistsDNAPageImpl", @"BlendViewController");
    if (page) {
        // The page is hosted by a controller of Spotify's page template, which is the top of the stack.
        SGRRegisterBarPages(^BOOL(UIViewController *top) { return SGRPageIsOrHolds(top, page); });
        %init(SGRSongDNABlend, SGRBlendController = page);
    } else {
        SGLog(@"class SongDNA_ArtistsDNAPageImpl.BlendViewController not found, Song DNA keeps Spotify's bar");
    }
}
