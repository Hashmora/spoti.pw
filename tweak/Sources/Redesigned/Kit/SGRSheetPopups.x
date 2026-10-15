// Redesign, iOS < 26: glass for the popups that were still Spotify's opaque grey. Each gets the queue's pane
// (SGRGlassSheetChrome) and the screen's own top corners:
//
//   Invite friends to your Jam         Jam_InvitationFlowImpl.ShareOptionsViewController
//   Jam settings (Guest controls)      a SwiftUI hosting controller of Jam_ParticipantSettingsPageImpl
//   Add to queue                       AssistedCuration_PageImpl / AssistedCuration_RecommendationsImpl
//   Sort by (a playlist)               SPTSortingFilteringPickerViewController
//   Filter and sort (Your Episodes)    FilterAndSort_PresentingImpl
//   Filter and sort (See all episodes) ShowPage_SortAndFilterImpl.SortAndFilterBottomSheetViewController
//   Song credits                       TrackCredits_CreditsPageImpl.CreditsViewController
//   Save in                            PlaylistCuration_AddToPlaylistImpl.ATPContainerViewController
//   Download using mobile data         Offline_ContentOffliningUIImpl.ElementViewController<DownloadOverCellularDialogElement>
//   Smart Reorder popups (Edit playlist) PlaylistMixing_MessagingImpl.MixingMessagingViewController
//   Share                              Share_MenuImpl.ShareMenuViewControllerV2
//   Listening modes                    SmartShuffle_CoreImpl.PlayModePickerViewController
//   Connect device menu (Log out)      Connect_ContextMenuPageImpl.ContextMenuViewController, pushed in the picker's sheet
//   About SongDNA (the info button)    SongDNA_AboutSongDNAPageImpl.AboutSongDNASheetViewController
//   Report a problem (a transcript)    Transcript_ReadAlongImpl.ReportReadAlongViewController
//   Rate show (a podcast's Rate chip)  Ratings_CommonImpl.RatingsAndReviewsRatePodcastViewController, inside the
//                                      page loader (Tome_PageLoaderViewImpl.SPTMusicClientPageLoaderView)
//
// The first seven are the same Navigation sheet (NavigationUI_SheetImpl.ContainerViewController, id=sheet-view),
// each holding its own controller. That class is Swift and generic for SwiftUI pages, so a sheet is recognised by
// part of the inner controller's name. The pane goes in from the sheet's own passes because its rows are built
// after the first layout; SGRRepaint.x keeps Spotify's grey clear in between.
//
// Sort by under the library's Recents button is not a Navigation sheet either: it is a card of the picker's own
// presentation (SPTSortingFilteringPresentationController), so it gets its pane by the card.
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
             @"FilterAndSort_PresentingImpl",
             @"ShowPage_SortAndFilterImpl",
             @"TrackCredits_CreditsPageImpl",
             @"PlaylistCuration_AddToPlaylistImpl",
             @"Offline_ContentOffliningUIImpl",
             @"PlaylistMixing_MessagingImpl",
             @"SongDNA_AboutSongDNAPageImpl"];
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

// The sheet Save in is in, while it is up: what the write-time hooks below test a view against.
static __weak UIView *sg_saveInSheet;

// Save in's wrappers are painted an opaque black (#000 or the page's #121212), which the pane's strip leaves alone
// (it takes only greys a view can see, SGIsVisibleColor) and the queue has none of: laid over the glass they made
// the popup near black. The full width bands that are black or Spotify's grey go clear, as in a list's rows.
// An opaque view with no fill is drawn over black, whatever its parent shows (see SGRGlass.m's clearListPaint, which
// takes the views below the page). The wrappers above it, between the page and the sheet's pane, are Spotify's and
// kept their flag, so the glass stayed black behind a tree with no paint left in it (trees/continuous/3.txt). Only
// below the pane, and only when there is one.
static UIView *paneOf(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:@"sheet-view"]) return v;
    }
    return nil;
}

static void clearOpaqueAbove(UIView *view) {
    UIView *pane = paneOf(view);
    if (!pane) return;
    if (sg_saveInSheet != pane) sg_saveInSheet = pane;
    for (UIView *v = view; v && v != pane; v = v.superview) {
        if (v.opaque) v.opaque = NO;
        if (v.layer.opaque) v.layer.opaque = NO;
        if (!SGKeepsColor(v) && v.layer.backgroundColor && CGColorGetAlpha(v.layer.backgroundColor) > 0.05) v.backgroundColor = UIColor.clearColor;
    }
}

// Every view below `view`, whatever its width: the flag the width-gated clearing leaves on the narrow views inside a
// row (the title stack, the artwork's holder) draws black over the glass just the same.
static void clearOpaqueBelow(UIView *view, int depth) {
    if (depth > 24) return;
    if (view.opaque) view.opaque = NO;
    if (view.layer.opaque) view.layer.opaque = NO;
    for (UIView *sub in view.subviews) clearOpaqueBelow(sub, depth + 1);
}

static void clearSaveInPaint(UIView *view) {
    UIView *sheet = sgr_sheetChromeRoot;
    if (view && sheet) SGRClearSheetCellPaint(view, sheet);
    if (view) {
        clearOpaqueAbove(view);
        clearOpaqueBelow(view, 0);
    }
}

// Save in is marked opaque by Spotify each time a row or wrapper is laid out, so clearing the flag on the passes above
// leaves it back on until the next one, and an opaque view with no fill is drawn black over the glass. The queue never
// had this: its grey is a fill, kept clear as it is written (SGRRepaint.x). The flag is kept clear the same way, as it is
// written, for every view inside this sheet.
static BOOL inSaveIn(UIView *view) {
    UIView *sheet = sg_saveInSheet;
    return sheet && view.window && SGIsInside(view, sheet);
}

%group SGRSaveInOpaque
%hook CALayer
- (void)setOpaque:(BOOL)opaque {
    if (opaque && sg_saveInSheet) {
        UIView *view = (UIView *)self.delegate;
        if ([view isKindOfClass:UIView.class] && view.layer == self && inSaveIn(view)) opaque = NO;
    }
    %orig(opaque);
}
%end
%end

// The page's own views (ATPMainView, and the strip under the list that holds Done), painted by Spotify whenever
// they are laid out, as the queue's two bars are (Redesigned/NowPlaying/QueueGlass.x): the paint, the opaque flag and the
// fade Spotify draws behind the button go each time.
static void clearSaveInView(UIView *view) {
    if (view.bounds.size.width < 1) return;
    CGColorRef paint = view.layer.backgroundColor;
    if (paint && CGColorGetAlpha(paint) > 0.05) view.backgroundColor = UIColor.clearColor;
    if (view.opaque) view.opaque = NO;
    if (view.layer.opaque) view.layer.opaque = NO;
    if ([view.layer isKindOfClass:CAGradientLayer.class]) {
        CAGradientLayer *gradient = (CAGradientLayer *)view.layer;
        if (gradient.colors) gradient.colors = nil;
    }
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer isKindOfClass:CAGradientLayer.class] && !layer.hidden) layer.hidden = YES;
    }
    clearOpaqueAbove(view);
}

%group SGRSaveInViews
%hook SGRSaveInMain
- (void)layoutSubviews {
    %orig;
    clearSaveInView((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    clearSaveInView((UIView *)self);
}
%end

%hook SGRSaveInDone
- (void)layoutSubviews {
    %orig;
    clearSaveInView((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    clearSaveInView((UIView *)self);
}
%end
%end

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

#pragma mark - the library's Sort by

// The Recents button over Liked Songs opens SPTSortingFilteringPickerViewController as a card under
// SPTSortingFilteringPresentationController (trees/continuous/2.txt): #282828 r=10 over a 0.6 scrim, the card
// being the view the presentation puts in its container. The same controller in a playlist's Navigation
// sheet is the sheet's to dress, above.
//
// Liked Songs' Sort by is the same picker inside a Navigation sheet (trees/continuous/3.txt), whose pane the sheet
// pass above already puts behind it. The picker's own view is not a second card there: giving it a pane too laid a
// second glass inside the first.
static void sortChrome(UIViewController *controller) {
    for (UIView *v = controller.viewIfLoaded; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:@"sheet-view"]) return;
    }
    UIPresentationController *presentation = controller.presentationController;
    if (![NSStringFromClass(presentation.class) isEqualToString:@"SPTSortingFilteringPresentationController"]) return;
    UIView *card = presentation.presentedView;
    if (card.bounds.size.width > 1) SGRGlassSheetView(card);
}

%group SGRSortPicker
%hook SGRSortPickerController
- (void)viewDidLayoutSubviews {
    %orig;
    sortChrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sortChrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    sortChrome((UIViewController *)self);
    // Its rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) sortChrome(weak);
        });
    }
}
%end
%end

#pragma mark - the podcast speed popup

// PodcastPlaybackSpeed_UIImpl.PlaybackSpeedView {0, 529} 390x315 #1F1F1F r=16 in a UITransitionView of a
// BottomSheetPresentationController's own (trees/continuous/22.txt). Beside it, not in it, sits a 28pt strip
// with the grabber and Spotify's Done button; Done goes (alpha, since a hidden Encore view can crash its
// stack), the swipe and the dimmed area close the popup. The round speed buttons are glass circles.
static char kDoneKey;

static void hideDone(UIView *sheet) {
    UIView *host = sheet.superview;
    for (UIView *strip in host.subviews) {
        if (strip == sheet || object_getClass(strip) != UIView.class) continue;
        for (UIView *sub in strip.subviews) {
            if (![sub.accessibilityLabel isEqualToString:@"Done"]) continue;
            if (sub.alpha != 0) sub.alpha = 0;
            sub.userInteractionEnabled = NO;
            objc_setAssociatedObject(strip, &kDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static void speedChrome(UIViewController *controller) {
    UIView *sheet = sheetNamed(controller.viewIfLoaded, @"PlaybackSpeedView", 0);
    if (!sheet || sheet.bounds.size.width < 1) return;
    SGRGlassSheetView(sheet);
    hideDone(sheet);
}

%group SGRSpeedPopup
%hook SGRSpeedController
- (void)viewDidLayoutSubviews {
    %orig;
    speedChrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    speedChrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    speedChrome((UIViewController *)self);
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) speedChrome(weak);
        });
    }
}
%end
%end

// The buttons: a glass circle inside each, and the translucent white Spotify fills them with taken off.
static char kRoundGlassKey;

static BOOL isFaintFill(CGColorRef color) {
    if (!color || CGColorGetAlpha(color) > 0.3) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    for (size_t i = 0; i + 1 < n; i++) if (c[i] < 0.9) return NO;
    return n >= 2;
}

%group SGRSpeedButtons
%hook SGRRoundButton
- (void)setBackgroundColor:(UIColor *)color {
    %orig(isFaintFill(color.CGColor) ? UIColor.clearColor : color);
}

- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if (button.bounds.size.width < 1) return;
    if (isFaintFill(button.layer.backgroundColor)) button.backgroundColor = UIColor.clearColor;
    SGRGlassInside(button, &kRoundGlassKey, MIN(button.bounds.size.width, button.bounds.size.height));
}
%end
%end

#pragma mark - Report a problem, and Rate show

// Transcript_ReadAlongImpl.ReportReadAlongView (trees/continuous/24.txt:902): the card the transcript's flag opens
// from the bottom of the screen, #1F1F1F with a layer mask of Spotify's own corners, over a 50% black dim. It is the
// controller's own view, so it is the pane; the mask would cut the glass to Spotify's corners, so it goes.
static void reportChrome(UIViewController *controller) {
    UIView *sheet = controller.viewIfLoaded;
    if (!sheet || sheet.bounds.size.width < 1) return;
    if (sheet.layer.mask) sheet.layer.mask = nil;
    SGRGlassSheetView(sheet);
}

// Ratings_CommonImpl's Rate show page (23.txt:1871-1906), a page sheet of its own navigation controller: the
// controller's view sits in the page loader's view, a plain #121212 the size of the sheet, which is the pane. Its
// footer fades to that #121212 (a gradient and a 34pt band under the Submit button), which would lay a dark bar
// over the glass; the band goes with the strip, the gradient is concealed.
static void rateChrome(UIViewController *controller) {
    UIView *pane = controller.viewIfLoaded.superview;
    if (!pane || pane.bounds.size.width < 300) return;
    SGRGlassSheetView(pane);
    SGForEachView(pane, ^(UIView *view) {
        if (![NSStringFromClass(view.class) hasSuffix:@"GradientView"] || view.layer.hidden) return;
        view.layer.hidden = YES;
        if (!view.layer.mask) view.layer.mask = [CALayer layer];
    });
}

// The grey comes back with the rows and the footer, after the first layout.
static void passes(UIViewController *controller, void (*chrome)(UIViewController *)) {
    __weak UIViewController *weak = controller;
    chrome(controller);
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}

%group SGRReportPopup
%hook SGRReportReadAlong
- (void)viewDidLayoutSubviews {
    %orig;
    reportChrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    reportChrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    passes((UIViewController *)self, reportChrome);
}
%end
%end

// The Rate show page is not in the sheet from the start: the page sheet opens on Tome_PageLoaderViewImpl's
// SPTMusicClientPageLoaderView with its spinner (SpinnerLoadingView) and the Rate controller is added once the page has
// loaded (23.txt:1691-1695, 1801-1805). Until then the loader's view, which is the pane, is Spotify's plain #121212,
// and rateChrome above only ran with the Rate controller: the sheet came up black for a beat and turned to glass
// when the page arrived. Save in has the same wait and solves it the same way (chrome() above, loadingIn): the pane
// goes in while the page is loading. A page sheet whose loader holds anything but the spinner and the Rate page is
// left as it is.
static BOOL isPageSheet(UIViewController *controller) {
    UIPresentationController *presentation = controller.navigationController.presentationController ?: controller.presentationController;
    Class pageSheet = NSClassFromString(@"_UIPageSheetPresentationController");
    return pageSheet && [presentation isKindOfClass:pageSheet];
}

// Loading, or holding the Rate page: no child of the loader but the spinner, or the one of Ratings_CommonImpl.
static BOOL loaderIsRate(UIViewController *loader) {
    for (UIViewController *child in loader.childViewControllers) {
        NSString *name = NSStringFromClass(child.class);
        if ([name containsString:@"Ratings_CommonImpl"]) return YES;
        if (![name containsString:@"SpinnerLoadingView"]) return NO;
    }
    return YES;
}

static void loaderChrome(UIViewController *loader) {
    UIView *pane = loader.viewIfLoaded;
    if (!pane || pane.bounds.size.width < 300 || !isPageSheet(loader) || !loaderIsRate(loader)) return;
    // The whole app is presented too (a UIDropShadowView r=47.3 under the window), and every page loader in it, the
    // Library's included, shows only its spinner for a moment: it was taken for the Rate sheet then, and its pane
    // kept the glass over the whole screen once the page had loaded (trees/continuous/2.txt), with the sheet chrome's
    // repaint hook clearing the avatar's fill. A page sheet is a card with a gap above it, never as tall as the screen.
    if (pane.bounds.size.height >= UIScreen.mainScreen.bounds.size.height - 1) return;
    if (pane.layer.mask) pane.layer.mask = nil;
    SGRGlassSheetView(pane);
}

%group SGRRateLoader
%hook SGRPageLoader
- (void)viewDidLayoutSubviews {
    %orig;
    loaderChrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    loaderChrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    passes((UIViewController *)self, loaderChrome);
}
%end
%end

%group SGRRatePopup
%hook SGRRatePodcast
- (void)viewDidLayoutSubviews {
    %orig;
    rateChrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    rateChrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    passes((UIViewController *)self, rateChrome);
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

#pragma mark - Save in's find bar

// The find field and the Sort button over Save in's playlists (trees/continuous/5.txt) are the grey boxes the
// playlist page's own find bar has (Playlist/PlaylistHeader.x), and become glass the same way. The bar is in the
// page twice: the one that scrolls with the list (a child of AddToPlaylistTableView) and the one the page shows while
// searching, with Cancel in place of Sort, so each is looked for from its own root.
static void glassFindBar(UIView *root) {
    static char kFieldKey, kButtonKey, kFieldGlassKey, kButtonGlassKey;
    SGRGlassFlatBox(SGRFindByIdentifier(root, @"Components.Header.UI.Toolbar.SearchField", &kFieldKey), &kFieldGlassKey);
    SGRGlassFlatBox(SGRFindByIdentifier(root, @"Components.Header.UI.Toolbar.ButtonContainer", &kButtonKey), &kButtonGlassKey);
}

// The list's own pass runs on every scroll as well, and the bar is made after the page's first layout.
%group SGRSaveInList
%hook UITableView
- (void)layoutSubviews {
    %orig;
    UIView *list = (UIView *)self;
    if (![list.accessibilityIdentifier isEqualToString:@"AddToPlaylistTableView"]) return;
    glassFindBar(list);
    glassFindBar(list.superview);
    // An opaque table is drawn over black however clear its fill is.
    if (list.opaque) list.opaque = NO;
    if (list.layer.opaque) list.layer.opaque = NO;
    if (list.layer.backgroundColor && CGColorGetAlpha(list.layer.backgroundColor) > 0.05) list.backgroundColor = UIColor.clearColor;
    clearOpaqueAbove(list);
}
%end
%end

#pragma mark - the Connect device menu

// A device's menu in the Connect picker (Log out and the like) is Connect_ContextMenuPageImpl's page pushed onto the
// picker's own navigation stack, inside its Navigation sheet (trees/continuous/14.txt). Its SwiftUI content is
// painted #1F1F1F (a _UIGraphicsView above the scroll view), which stood over the pane for the push and a beat
// after, until the sheet's own pass cleared it: the sheet does not lay out when a page is pushed in it. Like Save in,
// the page's own controller puts the pane in and clears the paint on its first layout.
static void connectMenuChrome(UIViewController *controller) {
    UIView *view = controller.viewIfLoaded;
    if (!view || view.bounds.size.width < 1) return;
    SGRGlassSheetChrome(view);
    clearSaveInPaint(view);
}

%group SGRConnectMenu
%hook SGRConnectMenuController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    connectMenuChrome((UIViewController *)self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    connectMenuChrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    passes((UIViewController *)self, connectMenuChrome);
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
        %init(SGRSaveInList);
        %init(SGRSaveInOpaque);
    }
    Class saveInMain = swiftClass(@"PlaylistCuration_AddToPlaylistImpl", @"ATPMainView");
    Class saveInDone = swiftClass(@"PlaylistCuration_AddToPlaylistImpl", @"ATPDoneButtonView");
    if (saveInMain && saveInDone) {
        %init(SGRSaveInViews, SGRSaveInMain = saveInMain, SGRSaveInDone = saveInDone);
    } else {
        SGLog(@"classes ATPMainView / ATPDoneButtonView not found, Save in may stay darker than the queue");
    }
    Class connectMenu = swiftClass(@"Connect_ContextMenuPageImpl", @"ContextMenuViewController");
    if (connectMenu) {
        %init(SGRConnectMenu, SGRConnectMenuController = connectMenu);
    } else {
        SGLog(@"class Connect_ContextMenuPageImpl.ContextMenuViewController not found, the Connect device menu keeps Spotify's grey");
    }
    Class picker = swiftClass(@"SmartShuffle_CoreImpl", @"PlayModePickerViewController");
    if (picker) {
        %init(SGRModePicker, SGRPlayModePicker = picker);
    } else {
        SGLog(@"class SmartShuffle_CoreImpl.PlayModePickerViewController not found, the Listening modes popup keeps Spotify's grey");
    }
    Class sortPicker = NSClassFromString(@"SPTSortingFilteringPickerViewController");
    if (sortPicker) {
        %init(SGRSortPicker, SGRSortPickerController = sortPicker);
    } else {
        SGLog(@"class SPTSortingFilteringPickerViewController not found, the library's Sort by keeps Spotify's grey");
    }
    Class speed = swiftClass(@"PodcastPlaybackSpeed_UIImpl", @"PlaybackSpeedViewController");
    if (speed) {
        %init(SGRSpeedPopup, SGRSpeedController = speed);
    } else {
        SGLog(@"class PodcastPlaybackSpeed_UIImpl.PlaybackSpeedViewController not found, the podcast speed popup keeps Spotify's grey");
    }
    Class round = NSClassFromString(@"_TtCO27PodcastPlaybackSpeed_ECMKit26PodcastDialogPlaybackSpeed11RoundButton");
    if (round) %init(SGRSpeedButtons, SGRRoundButton = round);
    Class report = swiftClass(@"Transcript_ReadAlongImpl", @"ReportReadAlongViewController");
    if (report) {
        %init(SGRReportPopup, SGRReportReadAlong = report);
    } else {
        SGLog(@"class Transcript_ReadAlongImpl.ReportReadAlongViewController not found, the transcript's Report a problem popup keeps Spotify's grey");
    }
    Class rate = swiftClass(@"Ratings_CommonImpl", @"RatingsAndReviewsRatePodcastViewController");
    if (rate) {
        %init(SGRRatePopup, SGRRatePodcast = rate);
    } else {
        SGLog(@"class Ratings_CommonImpl.RatingsAndReviewsRatePodcastViewController not found, the Rate show popup keeps Spotify's grey");
    }
    Class loader = swiftClass(@"Tome_PageLoaderViewImpl", @"SPTMusicClientPageLoaderView");
    if (loader) {
        %init(SGRRateLoader, SGRPageLoader = loader);
    } else {
        SGLog(@"class Tome_PageLoaderViewImpl.SPTMusicClientPageLoaderView not found, the Rate show popup is black until its page has loaded");
    }
    Class share = swiftClass(@"Share_MenuImpl", @"ShareMenuViewControllerV2");
    if (share) {
        %init(SGRSharePopup, SGRShareMenu = share);
    } else {
        SGLog(@"class Share_MenuImpl.ShareMenuViewControllerV2 not found, the share popup keeps Spotify's grey");
    }
}
