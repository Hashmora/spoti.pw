// Now playing redesign: glass for the queue sheet's own controls, and for the sheet itself. Clear and
// Edit (QueueHeaderView's PillButton) and the edit-mode toolbar's Move up / Remove / Clear selection are
// plain 10%-white capsules with nothing behind them (trees/continuous/8.txt 2026-09-26) -- the same flat
// chrome the playlist's sort/find toolbar had before PlaylistHeader.x glassed it.
//
// The sheet's own chrome (id=sheet-view, same as the ⋯ context menu's) never had a pane at all: nothing
// here hooked the queue's view controller for it the way Playlist/PlaylistMenu.x hooked the context
// menu's (trees/continuous/26.txt 2026-09-26, an opaque #1F1F1F all the way down and no glass view
// anywhere in it). SGRGlassSheetChrome (Redesigned/Kit/SGRGlass.h) is the same call the menu makes.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

// The exact runtime class NowPlaying_ECMKit.QueueHeader.UI.Private.PillButton prints itself as
// (NSStringFromClass, trees/continuous/8.txt): copied verbatim rather than re-derived, so a mistaken
// mangling can't silently miss every pill.
static NSString *const kPillButtonClass = @"_TtCOOO17NowPlaying_ECMKit11QueueHeader2UI7Private10PillButton";

static char kPillGlassKey, kChipGlassKey;

static void glassCapsule(UIView *box, const void *key) {
    if (!box) return;
    CGSize size = box.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    if (box.layer.cornerRadius != size.height / 2) box.layer.cornerRadius = size.height / 2;
    SGRGlassCapsuleInside(box, key, size, NO);
}

// Clear and Edit: wherever QueueHeaderView has put them this pass.
static void glassPills(UIView *root) {
    SGForEachView(root, ^(UIView *view) {
        if ([NSStringFromClass(view.class) isEqualToString:kPillButtonClass]) glassCapsule(view, &kPillGlassKey);
    });
}

// The edit-mode toolbar's three chips: each button's own wrapping capsule, found by the button's
// identifier and glassed one superview up.
static void glassChip(UIView *root, NSString *buttonIdentifier) {
    static char kBtnKey;
    UIView *button = SGRFindByIdentifier(root, buttonIdentifier, &kBtnKey);
    if (button && button.superview) glassCapsule(button.superview, &kChipGlassKey);
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
