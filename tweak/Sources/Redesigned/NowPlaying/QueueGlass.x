// Now playing redesign: glass for the queue sheet and its controls. Clear and Edit (QueueHeaderView's
// PillButton) and the edit-mode toolbar's Move up / Remove / Clear selection are flat 10%-white capsules,
// like the playlist's sort/find toolbar (trees/continuous/8.txt). The sheet itself (id=sheet-view, as in
// the ⋯ context menu) gets its pane from PGRGlassSheetChrome, the call Playlist/PlaylistMenu.x makes too. That
// call also clears the grey (#1F1F1F) of the queue's table and rows, and the Kit's repaint hook keeps it
// clear.
//
// The queue is built and painted after its first layout pass, so a chrome pass that runs only from
// viewDidLayoutSubviews missed the bar of Shuffle / Repeat / Timer and the edit toolbar (both
// #1F1F1F@1.00 in the dump taken just after opening, trees/continuous 2026-10-05) until a drag of the
// sheet laid it out again. It runs from the view's appearance and from the next turns of the run loop
// as well, and the two bars clear their own paint whenever it is laid down.
#import "Core/PGCore.h"
#import "Redesigned/Kit/PGRKit.h"

// NowPlaying_ECMKit.QueueHeader.UI.Private.PillButton, as NSStringFromClass prints it (trees/continuous/8.txt).
static NSString *const kPillButtonClass = @"_TtCOOO17NowPlaying_ECMKit11QueueHeader2UI7Private10PillButton";

static char kPillGlassKey, kChipGlassKey;

// Clear and Edit: wherever QueueHeaderView has put them this pass.
static void glassPills(UIView *root) {
    PGForEachView(root, ^(UIView *view) {
        if ([NSStringFromClass(view.class) isEqualToString:kPillButtonClass]) PGRGlassFlatBox(view, &kPillGlassKey);
    });
}

// The edit-mode toolbar's three chips: each button's own wrapping capsule, found by the button's
// identifier and glassed one superview up.
static void glassChip(UIView *root, NSString *buttonIdentifier) {
    static char kBtnKey;
    UIView *button = PGRFindByIdentifier(root, buttonIdentifier, &kBtnKey);
    if (button && button.superview) PGRGlassFlatBox(button.superview, &kChipGlassKey);
}

static void chrome(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (!root) return;
    PGRGlassSheetChrome(root);
    glassPills(root);
    glassChip(root, @"queue-edit-toolbar-move-up");
    glassChip(root, @"queue-edit-toolbar-remove");
    glassChip(root, @"queue-edit-toolbar-clear-selection");
}

%hook _TtC14Queue_ViewImpl19QueueViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
    // Whether the sheet is already above the queue's view here decides if the first frame is clean.
    PGLog(@"redesign queue: willAppear, sheet %@, view %@", pgr_sheetChromeRoot ? @"found" : @"NOT found",
          NSStringFromCGRect(((UIViewController *)self).viewIfLoaded.bounds));
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    for (NSNumber *delay in @[@0.0, @0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

// The two bars under the list: Queue_ViewImpl.SessionModifiersView and EditModeToolbarView, painted
// #1F1F1F by Spotify when they are made and each time their content changes.
static void clearBar(UIView *bar) {
    if (PGRIsSheetSurface(bar.layer.backgroundColor)) bar.backgroundColor = UIColor.clearColor;
}

%hook _TtC14Queue_ViewImpl20SessionModifiersView
- (void)layoutSubviews {
    %orig;
    clearBar((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    clearBar((UIView *)self);
}
%end

%hook _TtC14Queue_ViewImpl19EditModeToolbarView
- (void)layoutSubviews {
    %orig;
    clearBar((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    clearBar((UIView *)self);
}
%end

%ctor {
    if (!PGRedesignedUI()) return;
    %init;
    PGRequireClasses(@[@"_TtC14Queue_ViewImpl19QueueViewController"]);
}
