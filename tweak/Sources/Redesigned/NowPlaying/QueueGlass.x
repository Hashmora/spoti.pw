// Now playing redesign: glass for the queue sheet and its controls. Clear and Edit (QueueHeaderView's
// PillButton) and the edit-mode toolbar's Move up / Remove / Clear selection are flat 10%-white capsules,
// like the playlist's sort/find toolbar, and so is the Reshuffle capsule over the list. The sheet itself (id=sheet-view, as in
// the ⋯ context menu) gets its pane from SGRGlassSheetChrome, the call Playlist/PlaylistMenu.x makes too. That
// call also clears the grey (#1F1F1F) of the queue's table and rows, and the Kit's repaint hook keeps it
// clear.
//
// Reshuffle (and any other move of rows) leaves the rows that changed place painted #1F1F1F again, the cell and the
// stack inside it (trees/continuous/1.txt: every played-through QueueCell and its TrackRowQueue.Cell stack, visible
// and hidden, still grey with the glass clear around them) until a scroll lays the rows out anew. The sheet-wide hooks
// of SGRRepaint.x did not catch that paint, and a row that only changes place gets no layout pass of its own, so
// nothing cleared it. The cells clear their own grey now, as it is painted, as they are selected, attached or laid out,
// and the table's reloads and moves run a few passes over its rows.
//
// The queue is built and painted after its first layout pass, so a chrome pass that runs only from
// viewDidLayoutSubviews missed the bar of Shuffle / Repeat / Timer and the edit toolbar (both #1F1F1F)
// until a drag of the sheet laid it out again. It runs from the view's appearance and from the next turns of the run loop
// as well, and the two bars clear their own paint whenever it is laid down.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

// NowPlaying_ECMKit.QueueHeader.UI.Private.PillButton, as NSStringFromClass prints it.
static NSString *const kPillButtonClass = @"_TtCOOO17NowPlaying_ECMKit11QueueHeader2UI7Private10PillButton";

static char kCloseGlassKey, kCloseKey, kPillGlassKey, kChipGlassKey, kReshuffleKey, kReshuffleGlassKey, kPlayKey;

// Queue_ViewImpl.QueueCell, as NSStringFromClass prints it.
static NSString *const kQueueCellClass = @"_TtC14Queue_ViewImpl9QueueCell";

// The grey of one row of the queue: the cell and every band inside it nearly as wide as the cell (the stack the element
// framework wraps the row in). Narrow ones stay (the cover's placeholder square, a badge): they are their own paint.
static void clearRowPaint(UIView *view, CGFloat wide, int depth) {
    if (!view || depth > 12 || wide < 1) return;   // wide 0: the cell has no size yet; the pass that gives it one does it
    if (!SGKeepsColor(view) && view.bounds.size.width >= wide) {
        CGColorRef paint = view.layer.backgroundColor;
        if (paint && SGRIsSheetSurface(paint)) view.backgroundColor = UIColor.clearColor;
        // An opaque view with no fill is drawn over black (SGRGlass.m's clearListPaint).
        if (view.opaque || view.layer.opaque) {
            view.opaque = NO;
            view.layer.opaque = NO;
        }
    }
    for (UIView *sub in view.subviews) clearRowPaint(sub, wide, depth + 1);
}

static void clearCell(UIView *cell) {
    clearRowPaint(cell, cell.bounds.size.width * SGRSheetBandShare, 0);
}

// Every QueueCell under `scope`, hidden ones (the copies a move leaves in the table) included.
static void clearQueueRows(UIView *scope) {
    Class cellClass = NSClassFromString(kQueueCellClass);
    if (!scope || !cellClass) return;
    SGForEachView(scope, ^(UIView *view) {
        if ([view isKindOfClass:cellClass]) clearCell(view);
    });
}

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

// The edit mode's close cross (id=queue-close-edit-button, top right, 32pt): a glass circle like the other round controls.
static void glassClose(UIView *root) {
    UIView *button = SGRFindByIdentifier(root, @"queue-close-edit-button", &kCloseKey);
    if (button && button.bounds.size.width >= 1) SGRGlassInside(button, &kCloseGlassKey, button.bounds.size.width);
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
    glassClose(root);
    UIView *play = SGRFindByIdentifier(root, @"header-play-button", &kPlayKey);
    if (play) flattenPlay(play);
    glassChip(root, @"queue-edit-toolbar-move-up");
    glassChip(root, @"queue-edit-toolbar-remove");
    glassChip(root, @"queue-edit-toolbar-clear-selection");
    clearQueueRows(root);
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

// The rows themselves. Spotify paints the cell and its stack again as a row is configured, moved, picked up or let go,
// from layout passes that a plain change of place does not run.
%hook _TtC14Queue_ViewImpl9QueueCell
- (void)layoutSubviews {
    %orig;
    clearCell((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) clearCell((UIView *)self);
}

- (void)didMoveToSuperview {
    %orig;
    if (((UIView *)self).superview) clearCell((UIView *)self);
}

- (void)setBackgroundColor:(UIColor *)color {
    if (color && SGRIsSheetSurface(color.CGColor)) color = UIColor.clearColor;
    %orig(color);
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    %orig;
    clearCell((UIView *)self);
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    %orig;
    clearCell((UIView *)self);
}

- (void)addSubview:(UIView *)view {
    %orig;
    clearRowPaint(view, ((UIView *)self).bounds.size.width * SGRSheetBandShare, 1);
}
%end

// Reshuffle reloads the list or moves its rows, and Spotify paints the rows that changed place on its own turns of the
// run loop after that. A few passes over the table's rows follow each reload and move, as the sheet's own chrome gets
// after it appears.
static void clearTableLater(UITableView *table) {
    UIView *root = sgr_sheetChromeRoot;
    if (!root || !SGIsInside(table, root)) return;
    __weak UITableView *weak = table;
    for (NSNumber *delay in @[@0.0, @0.1, @0.3, @0.7]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UITableView *shown = weak;
            if (shown.window) clearQueueRows(shown);
        });
    }
}

%hook UITableView
- (void)reloadData {
    %orig;
    clearTableLater((UITableView *)self);
}

- (void)endUpdates {
    %orig;
    clearTableLater((UITableView *)self);
}

- (void)moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    %orig;
    clearTableLater((UITableView *)self);
}

- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(BOOL))completion {
    %orig;
    clearTableLater((UITableView *)self);
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
    SGRequireClasses(@[@"_TtC14Queue_ViewImpl19QueueViewController", @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView", kQueueCellClass]);
}
