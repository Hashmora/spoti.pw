// Redesign, iOS < 26: glass for the popups that were still Spotify's opaque grey, so every one of them has the
// queue's pane (the heavy blur, the dark body and the rim of SGRGlassSheetChrome) and the screen's own top
// corners instead of Spotify's 16:
//
//   Invite friends to your Jam         Jam_InvitationFlowImpl.ShareOptionsViewController
//   Jam settings (Guest controls)      a SwiftUI hosting controller of Jam_ParticipantSettingsPageImpl
//   Add to queue                       AssistedCuration_PageImpl / AssistedCuration_RecommendationsImpl
//   Sort by (a playlist, the library)  SPTSortingFilteringPickerViewController
//   Song credits                       TrackCredits_CreditsPageImpl.CreditsViewController
//   Save in                            PlaylistCuration_AddToPlaylistImpl.ATPContainerViewController
//   Share                              Share_MenuImpl.ShareMenuViewControllerV2 (below)
//
// The first six are one and the same Navigation sheet the queue, the Connect picker and the ⋯ menu are
// (NavigationUI_SheetImpl.ContainerViewController, id=sheet-view, #1F1F1F or #282828, trees/continuous 2026-10-11
// 2 to 9), each holding its own controller. That controller's class is Swift and, for a SwiftUI page, a generic
// one with the page's types in its name, so the sheets are told apart by a part of the name of the controller
// inside them rather than hooked one by one; any other sheet (the Create menu, which glasses its card alone)
// is left to its own file. The pane goes in from the sheet's own passes, since the rows are built after the
// first layout and Spotify paints its grey back on later ones (SGRRepaint.x keeps it clear in between).
//
// The share menu is not Navigation's: its ShareMenuSheetView is presented over the full screen by UIKit and has
// no "sheet-view" in it (trees/continuous/10.txt), so its pane goes behind that view by name.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

// A Swift class by module and name, under the mangled spelling or the dotted one the trees print; nil when the
// app has neither.
static Class swiftClass(NSString *module, NSString *name) {
    NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@", (unsigned long)module.length, module, (unsigned long)name.length, name];
    return NSClassFromString(mangled) ?: NSClassFromString([NSString stringWithFormat:@"%@.%@", module, name]);
}

// A part of the class name of the controller that fills each sheet above: the module, where every class of the
// module is that page, and the class itself where the module is UIKit's old picker.
static NSArray<NSString *> *contentMarkers(void) {
    return @[@"Jam_InvitationFlowImpl",
             @"Jam_ParticipantSettingsPageImpl",
             @"AssistedCuration_",
             @"SPTSortingFilteringPickerViewController",
             @"TrackCredits_CreditsPageImpl",
             @"PlaylistCuration_AddToPlaylistImpl"];
}

static BOOL isContent(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    for (NSString *marker in contentMarkers()) {
        if ([name containsString:marker]) return YES;
    }
    return NO;
}

// The first controller inside the sheet's that is one of those pages, looked for through the hosting controllers
// and navigation controllers Spotify wraps it in.
static UIViewController *contentIn(UIViewController *controller, int depth) {
    if (depth > 10) return nil;
    for (UIViewController *child in controller.childViewControllers) {
        if (isContent(child)) return child;
        UIViewController *inner = contentIn(child, depth + 1);
        if (inner) return inner;
    }
    return nil;
}

static void chrome(UIViewController *sheet) {
    UIViewController *content = contentIn(sheet, 0);
    UIView *root = content.viewIfLoaded;
    if (root) SGRGlassSheetChrome(root);
}

static void afterAppear(UIViewController *sheet) {
    __weak UIViewController *weak = sheet;
    chrome(sheet);
    // The rows are built after the first layout and the grey comes back with them.
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}

%group SGRSheetPopups
%hook SGRSheetContainer
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
    afterAppear((UIViewController *)self);
}
%end
%end

#pragma mark - the share menu

// Share_MenuImpl.ShareMenuSheetView: the card the menu draws on its own, #1F1F1F r=16, a good deal taller than the
// screen so it can be pulled up.
static UIView *shareSheetIn(UIView *root, int depth) {
    if (!root || depth > 4) return nil;
    if ([NSStringFromClass(root.class) hasSuffix:@"ShareMenuSheetView"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = shareSheetIn(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

static void shareChrome(UIViewController *controller) {
    UIView *sheet = shareSheetIn(controller.viewIfLoaded, 0);
    if (sheet && sheet.bounds.size.width > 1) SGRGlassSheetView(sheet);
}

%group SGRSharePopup
%hook SGRShareMenu
- (void)viewDidLayoutSubviews {
    %orig;
    shareChrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    shareChrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    shareChrome((UIViewController *)self);
    // Its rows and the preview cards are laid out after the first pass.
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) shareChrome(weak);
        });
    }
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (@available(iOS 26.0, *)) return;   // from iOS 26 the system draws its own glass; this is the legacy glass's
    Class sheet = swiftClass(@"NavigationUI_SheetImpl", @"ContainerViewController");
    if (sheet) {
        %init(SGRSheetPopups, SGRSheetContainer = sheet);
    } else {
        SGLog(@"class NavigationUI_SheetImpl.ContainerViewController not found, the Jam, Add to queue, Sort by, credits and Save in popups keep Spotify's grey");
    }
    Class share = swiftClass(@"Share_MenuImpl", @"ShareMenuViewControllerV2");
    if (share) {
        %init(SGRSharePopup, SGRShareMenu = share);
    } else {
        SGLog(@"class Share_MenuImpl.ShareMenuViewControllerV2 not found, the share popup keeps Spotify's grey");
    }
}
