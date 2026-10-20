// The Library's New Episodes (SPTYourLibraryPodcastNewEpisodesViewController, from the podcasts filter): the redesign's
// bar over the list (Pages/PageBar.m).
//
// Tree (trees/continuous/21.txt): the page holds SPTPodcastYourLibraryEpisodesViewController, whose list (a UITableView)
// is the size of the screen on #000000, so it already runs under the bar; over it the navigation controller's blur
// (390x91, #1C1C1C@0.73) and SPNavigationBar with Back and the title "New Episodes" as a label, nothing at the trailing
// edge. So the blur goes, the title sits white on a glass capsule and Back is a glass circle pinned to the corner, as on
// Recents.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

%group SGRNewEpisodes
%hook SGRNewEpisodesController
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
    // The bar's button and title are made after the first layout.
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
    Class page = NSClassFromString(@"SPTYourLibraryPodcastNewEpisodesViewController");
    if (page) {
        SGRRegisterBarPages(^BOOL(UIViewController *top) { return [top isKindOfClass:page]; });
        %init(SGRNewEpisodes, SGRNewEpisodesController = page);
    } else {
        SGLog(@"class SPTYourLibraryPodcastNewEpisodesViewController not found, New Episodes keeps Spotify's bar");
    }
}
