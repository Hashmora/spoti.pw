// Now playing redesign: glass for the queue sheet and its controls. Clear and Edit (QueueHeaderView's
// PillButton) and the edit-mode toolbar's Move up / Remove / Clear selection are flat 10%-white capsules,
// like the playlist's sort/find toolbar (trees/continuous/8.txt). The sheet itself (id=sheet-view, as in
// the ⋯ context menu) gets its pane from SGRGlassSheetChrome, the call Playlist/PlaylistMenu.x makes too. That
// call also clears the grey (#1F1F1F) of the queue's table and rows, and the Kit's repaint hook keeps it
// clear (trees/continuous 2026-10-05: the list stayed opaque under a glass header and footer).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

// NowPlaying_ECMKit.QueueHeader.UI.Private.PillButton, as NSStringFromClass prints it (trees/continuous/8.txt).
static NSString *const kPillButtonClass = @"_TtCOOO17NowPlaying_ECMKit11QueueHeader2UI7Private10PillButton";

static char kPillGlassKey, kChipGlassKey;

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

%hook _TtC14Queue_ViewImpl19QueueViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *root = ((UIViewController *)self).viewIfLoaded;
    if (!root) return;
    SGRGlassSheetChrome(root);
    glassPills(root);
    glassChip(root, @"queue-edit-toolbar-move-up");
    glassChip(root, @"queue-edit-toolbar-remove");
    glassChip(root, @"queue-edit-toolbar-clear-selection");
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC14Queue_ViewImpl19QueueViewController"]);
}
