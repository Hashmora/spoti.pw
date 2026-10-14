#import "Core/SGCore.h"
#import "SGRChips.h"
#import "SGRGlass.h"
#import "SGRRestyle.h"

// Encore_ChipsKit's own classes, as the trees print them (trees/continuous/1.txt:27-31).
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

// A selected chip is painted a solid colour of its own; an unselected one a translucent white, or on the radio's
// chips (SessionControl, trees/continuous/4.txt) Spotify's opaque #2A2A2A, which is a dark grey and no colour.
static BOOL pillIsSelected(UIView *pill) {
    CGColorRef color = pill.layer.backgroundColor;
    return color && CGColorGetAlpha(color) > 0.3 && !SGRIsSheetSurface(color);
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

static void watchChip(UIView *chip) {
    if (objc_getAssociatedObject(chip, &kChipWatchedKey)) return;
    if (SGRObserveLayout(chip, ^(UIView *view) { glassChip(view); })) {
        objc_setAssociatedObject(chip, &kChipWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

void SGRGlassChipsIn(UIView *root) {
    SGForEachView(root, ^(UIView *v) {
        if (!isChip(v)) return;
        glassChip(v);
        watchChip(v);
    });
}

BOOL SGRIsDressedChipPill(UIView *view) {
    UIView *chip = view.superview;
    if (![NSStringFromClass(view.class) isEqualToString:kPillClass] || !isChip(chip)) return NO;
    return objc_getAssociatedObject(chip, &kChipWatchedKey) != nil;
}

void SGRDressedChipPainted(UIView *chip) {
    if (chip.window && isChip(chip)) glassChip(chip);
}
