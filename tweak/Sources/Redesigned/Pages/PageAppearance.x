// Redesign: every page of Spotify's navigation stacks is dark, whatever the phone is set to.
//
// Spotify is dark in both appearances. Its own -[SPNavigationController viewDidLoad] makes the stack dark only
// while +[SPTLiquidGlass isEnabled] (see Navbar/TabBar.x), which the redesign does not rely on, so on a phone in
// light mode the stack stayed light until the app had been left and entered again: the section headings of
// Listening stats (Top artists, Top songs) were black on black, a title on its glass capsule was black on white
// glass, and Settings, Your Updates and Your Premium did the same (device, 2026-10-15, 19.txt: the bar's title
// "Chapters" is #000000 and its capsule white).
//
// So the navigation controller, its view and its bar are given the dark appearance. Every page under them
// inherits it, the bar's glass and its labels included, and no page has to override its own.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static void makeDark(UINavigationController *navigation) {
    if (navigation.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIView *view = navigation.viewIfLoaded;
    if (view && view.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UINavigationBar *bar = navigation.navigationBar;
    if (bar.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}

%hook SPNavigationController
- (void)viewDidLoad {
    %orig;
    makeDark((UINavigationController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    makeDark((UINavigationController *)self);
}

// Spotify writes the style itself from its own passes; it is put back wherever it was changed.
- (void)viewDidLayoutSubviews {
    %orig;
    makeDark((UINavigationController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"SPNavigationController"]);
}
