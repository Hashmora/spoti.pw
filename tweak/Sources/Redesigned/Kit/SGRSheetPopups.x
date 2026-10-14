// Redesign, iOS < 26: glass for the popups that were still Spotify's opaque grey. Each gets the queue's pane
// (SGRGlassSheetChrome) and the screen's own top corners:
//
//   Invite friends to your Jam         Jam_InvitationFlowImpl.ShareOptionsViewController
//   Jam settings (Guest controls)      a SwiftUI hosting controller of Jam_ParticipantSettingsPageImpl
//   Add to queue                       AssistedCuration_PageImpl / AssistedCuration_RecommendationsImpl
//   Sort by (a playlist, the library)  SPTSortingFilteringPickerViewController
//   Song credits                       TrackCredits_CreditsPageImpl.CreditsViewController
//   Save in                            PlaylistCuration_AddToPlaylistImpl.ATPContainerViewController
//   Download using mobile data         Offline_ContentOffliningUIImpl.ElementViewController<DownloadOverCellularDialogElement>
//   Share                              Share_MenuImpl.ShareMenuViewControllerV2
//   Listening modes                    SmartShuffle_CoreImpl.PlayModePickerViewController
//
// The first seven are the same Navigation sheet (NavigationUI_SheetImpl.ContainerViewController, id=sheet-view),
// each holding its own controller. That class is Swift and generic for SwiftUI pages, so a sheet is recognised by
// part of the inner controller's name. The pane goes in from the sheet's own passes because its rows are built
// after the first layout; SGRRepaint.x keeps Spotify's grey clear in between.
//
// Share and Listening modes are not Navigation sheets: ShareMenuSheetView is presented by UIKit with no
// sheet-view in it, and PlayModePickerView is placed by a presentation controller of its own, so each gets
// its pane by name.
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
             @"PlaylistCuration_AddToPlaylistImpl",
             @"Offline_ContentOffliningUIImpl"];
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

// Whether a page of Spotify's template that loads its content later is in the sheet: Save in is one, and its
// ATPContainerViewController is only added once the page has loaded.
static BOOL loadingIn(UIViewController *controller, int depth) {
    if (depth > 10) return NO;
    for (UIViewController *child in controller.childViewControllers) {
        if ([NSStringFromClass(child.class) containsString:@"LoadableTemplateViewController"]) return YES;
        if (loadingIn(child, depth + 1)) return YES;
    }
    return NO;
}

static char kPendingPaneKey;

// Save in's wrappers are painted an opaque black (#000 or the page's #121212), which the pane's strip leaves alone
// (it takes only greys a view can see, SGIsVisibleColor) and the queue has none of: laid over the glass they made
// the popup near black. The full width bands that are black or Spotify's grey go clear, as in a list's rows.
static void clearSaveInPaint(UIView *view) {
    UIView *sheet = sgr_sheetChromeRoot;
    if (view && sheet) SGRClearSheetCellPaint(view, sheet);
}

static void chrome(UIViewController *sheet) {
    UIViewController *content = contentIn(sheet, 0);
    UIView *root = content.viewIfLoaded;
    if (root) {
        SGRGlassSheetChrome(root);
        if ([NSStringFromClass(content.class) containsString:@"PlaylistCuration_AddToPlaylistImpl"]) clearSaveInPaint(root);
        return;
    }
    // The content is not in yet, but the sheet is already up and grey: while a loading page is in it, the pane
    // goes in anyway, so the first frames are glass and not Spotify's grey that glass replaces a moment later.
    if (loadingIn(sheet, 0)) {
        UIView *pane = SGRFindByIdentifier(sheet.viewIfLoaded, @"sheet-view", &kPendingPaneKey);
        if (pane) {
            SGRGlassSheetChrome(pane);
            clearSaveInPaint(pane);
        }
    }
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
static UIView *sheetNamed(UIView *root, NSString *suffix, int depth) {
    if (!root || depth > 4) return nil;
    if ([NSStringFromClass(root.class) hasSuffix:suffix]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = sheetNamed(sub, suffix, depth + 1);
        if (found) return found;
    }
    return nil;
}

static void shareChrome(UIViewController *controller) {
    UIView *sheet = sheetNamed(controller.viewIfLoaded, @"ShareMenuSheetView", 0);
    if (sheet && sheet.bounds.size.width > 1) SGRGlassSheetView(sheet);
}

static void pickerChrome(UIViewController *controller) {
    UIView *sheet = sheetNamed(controller.viewIfLoaded, @"PlayModePickerView", 0);
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

#pragma mark - the listening modes picker

%group SGRModePicker
%hook SGRPlayModePicker
- (void)viewDidLayoutSubviews {
    %orig;
    pickerChrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    pickerChrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    pickerChrome((UIViewController *)self);
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) pickerChrome(weak);
        });
    }
}
%end
%end

#pragma mark - Save in, from the page's own controller

// The page's own controller is hooked as well as the sheet's: it is the first thing that knows the content is
// in, so the pane goes in on its first layout and not on the sheet's next pass.
%group SGRSaveIn
%hook SGRSaveInContainer
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIView *view = ((UIViewController *)self).viewIfLoaded;
    SGRGlassSheetChrome(view);
    clearSaveInPaint(view);
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *view = ((UIViewController *)self).viewIfLoaded;
    SGRGlassSheetChrome(view);
    clearSaveInPaint(view);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class sheet = swiftClass(@"NavigationUI_SheetImpl", @"ContainerViewController");
    if (sheet) {
        %init(SGRSheetPopups, SGRSheetContainer = sheet);
    } else {
        SGLog(@"class NavigationUI_SheetImpl.ContainerViewController not found, the Jam, Add to queue, Sort by, credits and Save in popups keep Spotify's grey");
    }
    Class saveIn = swiftClass(@"PlaylistCuration_AddToPlaylistImpl", @"ATPContainerViewController");
    if (saveIn) {
        %init(SGRSaveIn, SGRSaveInContainer = saveIn);
    }
    Class picker = swiftClass(@"SmartShuffle_CoreImpl", @"PlayModePickerViewController");
    if (picker) {
        %init(SGRModePicker, SGRPlayModePicker = picker);
    } else {
        SGLog(@"class SmartShuffle_CoreImpl.PlayModePickerViewController not found, the Listening modes popup keeps Spotify's grey");
    }
    Class share = swiftClass(@"Share_MenuImpl", @"ShareMenuViewControllerV2");
    if (share) {
        %init(SGRSharePopup, SGRShareMenu = share);
    } else {
        SGLog(@"class Share_MenuImpl.ShareMenuViewControllerV2 not found, the share popup keeps Spotify's grey");
    }
}
