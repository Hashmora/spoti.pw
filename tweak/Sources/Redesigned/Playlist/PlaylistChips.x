// Playlist redesign, iOS < 26: the chips over a playlist's first track (the genres of Liked Songs) on glass.
//
// Tree (trees/continuous/1.txt:24-131): a cell of the list holding CollectionSongs_PlaylistImpl's
// CSNestedChipsElement, whose NestedChipsView scrolls a row of Encore ChipViews. A chip is a PillView, the
// capsule (#FFFFFF@0.10 r=16, clipped), under a stack with the label. The pill's fill goes and a glass capsule
// stands behind it, the way the library's chips have theirs (Library/LibraryHeader.x); a selected chip keeps the
// solid colour it is painted, which is never the translucent white.
//
// Spotify paints the fill again as a chip is selected or let go, with no layout, so SGRRepaint.x keeps the
// neutral tint off the pill and tells the chip (SGRPlaylistChipPainted).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"

static NSString *const kChipClass = @"_TtCE15Encore_ChipsKitO16EncoreFoundation6Encore8ChipView";
static NSString *const kPillClass = @"_TtCE15Encore_ChipsKitO16EncoreFoundation6Encore8PillView";
static NSString *const kRowClass = @"_TtCE15Encore_ChipsKitO16EncoreFoundation6Encore15NestedChipsView";

static char kChipGlassKey, kChipWatchedKey;

static BOOL isChip(UIView *view) {
    return [NSStringFromClass(view.class) isEqualToString:kChipClass];
}

static UIView *pillOf(UIView *chip) {
    for (UIView *sub in chip.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:kPillClass]) return sub;
    }
    return nil;
}

BOOL SGRPlaylistIsChipPill(UIView *view) {
    if (![NSStringFromClass(view.class) isEqualToString:kPillClass] || !isChip(view.superview)) return NO;
    return SGIsInside(view, sgr_playlistRoot);
}

// A selected chip is painted a solid colour of its own; an unselected one a translucent white.
static BOOL pillIsSelected(UIView *pill) {
    CGColorRef color = pill.layer.backgroundColor;
    return color && CGColorGetAlpha(color) > 0.3;
}

// A chip grows under a finger with the legacy glass (SGGlassInteractive), and every view up to the row clips to
// its bounds, which cut the grown capsule off at its edges.
static void unclipChip(UIView *chip) {
    if (!SGUseLegacyGlass()) return;
    for (UIView *v = chip.superview; v; v = v.superview) {
        if (v.clipsToBounds) v.clipsToBounds = NO;
        if ([NSStringFromClass(v.class) isEqualToString:kRowClass]) break;
    }
}

static void glassChip(UIView *chip) {
    CGSize size = chip.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    unclipChip(chip);
    UIView *pill = pillOf(chip);
    if (pill && pillIsSelected(pill)) {
        // Under the colour already; hidden as well, so no rim of it shows round the capsule's edge.
        UIView *glass = objc_getAssociatedObject(chip, &kChipGlassKey);
        if (glass && !glass.hidden) glass.hidden = YES;
        return;
    }
    if (pill && pill.layer.backgroundColor) pill.layer.backgroundColor = NULL;
    SGRGlassCapsuleInside(chip, &kChipGlassKey, size, NO);
}

// Picking a chip lays the row out again at new widths, which reaches neither the cell nor the page: the chip is
// watched for its own layout and its glass is sized again on every pass of it.
static void watchChip(UIView *chip) {
    if (objc_getAssociatedObject(chip, &kChipWatchedKey)) return;
    if (SGRObserveLayout(chip, ^(UIView *view) { glassChip(view); })) {
        objc_setAssociatedObject(chip, &kChipWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

void SGRPlaylistChipPainted(UIView *chip) {
    if (chip.window && isChip(chip)) glassChip(chip);
}

static BOOL isChipsCell(UIView *cell) {
    for (UIView *sub in cell.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"CSNestedChipsElement"]) return YES;
    }
    return NO;
}

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (void)layoutSubviews {
    %orig;
    UIView *cell = (UIView *)self;
    if (!isChipsCell(cell) || !SGRPlaylistHeaderOf(cell)) return;
    SGForEachView(cell, ^(UIView *v) {
        if (!isChip(v)) return;
        glassChip(v);
        watchChip(v);
    });
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"_TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell"]);
}
