// Now playing redesign: glass for the queue sheet and its controls. Clear and Edit (QueueHeaderView's
// PillButton) and the edit-mode toolbar's Move up / Remove / Clear selection are flat 10%-white capsules,
// like the playlist's sort/find toolbar, and so is the Reshuffle capsule over the list. The sheet itself (id=sheet-view, as in
// the ⋯ context menu) gets its pane from SGRGlassSheetChrome, the call Playlist/PlaylistMenu.x makes too. That
// call also clears the grey (#1F1F1F) of the queue's table and rows, and the Kit's repaint hook keeps it
// clear.
//
// The queue is built and painted after its first layout pass, so a chrome pass that runs only from
// viewDidLayoutSubviews missed the bar of Shuffle / Repeat / Timer and the edit toolbar (both #1F1F1F)
// until a drag of the sheet laid it out again. It runs from the view's appearance and from the next turns of the run loop
// as well, and the two bars clear their own paint whenever it is laid down.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

// NowPlaying_ECMKit.QueueHeader.UI.Private.PillButton, as NSStringFromClass prints it.
static NSString *const kPillButtonClass = @"_TtCOOO17NowPlaying_ECMKit11QueueHeader2UI7Private10PillButton";

static char kPillGlassKey, kChipGlassKey, kReshuffleKey, kReshuffleGlassKey, kPlayKey;

// Clear and Edit: wherever QueueHeaderView has put them this pass.
static void glassPills(UIView *root) {
    SGForEachView(root, ^(UIView *view) {
        if ([NSStringFromClass(view.class) isEqualToString:kPillButtonClass]) SGRGlassFlatBox(view, &kPillGlassKey);
    });
}

// The edit-mode toolbar's three chips: each button's own wrapping capsule, found by the button's
// identifier and glassed one superview up.
static void glassChip(UIView *root, NSString *buttonIdentifier) {
    static char kBtnKey;
    UIView *button = SGRFindByIdentifier(root, buttonIdentifier, &kBtnKey);
    if (button && button.superview) SGRGlassFlatBox(button.superview, &kChipGlassKey);
}

// The Reshuffle capsule (Encore Primary button, id=reshuffle-button) that floats over the list once the
// queue has been played through: it is the sheet's one primary action, so its glass carries the white film
// (prominent) and reads a step brighter than Clear and Edit instead of vanishing into the sheet.
static void glassReshuffle(UIView *root) {
    UIView *button = SGRFindByIdentifier(root, @"reshuffle-button", &kReshuffleKey);
    if (!button) return;
    if (@available(iOS 26.0, *)) return;
    CGSize size = button.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    if (button.backgroundColor != UIColor.clearColor) button.backgroundColor = UIColor.clearColor;
    if (button.layer.cornerRadius != size.height / 2) button.layer.cornerRadius = size.height / 2;
    if (button.layer.cornerCurve != kCACornerCurveContinuous) button.layer.cornerCurve = kCACornerCurveContinuous;
    BOOL grows = SGUseLegacyGlass();
    if (button.layer.masksToBounds != !grows) button.layer.masksToBounds = !grows;
    SGRGlassCapsuleInside(button, &kReshuffleGlassKey, size, YES);
}

// The Now playing row's play / pause button (id=header-play-button, 15.txt): Spotify draws a dark grey shadow
// under it that runs down over the glass. Taken off its layers, and again whenever Spotify lays it out.
static void flattenPlay(UIView *button) {
    if (button.layer.shadowOpacity > 0) button.layer.shadowOpacity = 0;
    for (UIView *v in button.subviews) flattenPlay(v);
}

static void chrome(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (!root) return;
    SGRGlassSheetChrome(root);
    glassPills(root);
    glassReshuffle(root);
    UIView *play = SGRFindByIdentifier(root, @"header-play-button", &kPlayKey);
    if (play) flattenPlay(play);
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
    SGLog(@"redesign queue: willAppear, sheet %@, view %@", sgr_sheetChromeRoot ? @"found" : @"NOT found",
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
    if (SGRIsSheetSurface(bar.layer.backgroundColor)) bar.backgroundColor = UIColor.clearColor;
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

// Spotify sets the shadow as the button's state changes, play to pause included, which no pass of the sheet follows.
%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if (![button.accessibilityIdentifier isEqualToString:@"header-play-button"]) return;
    for (UIResponder *r = button; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        if ([NSStringFromClass(r.class) containsString:@"Queue_ViewImpl"]) flattenPlay(button);
        return;
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"_TtC14Queue_ViewImpl19QueueViewController", @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView"]);
}
