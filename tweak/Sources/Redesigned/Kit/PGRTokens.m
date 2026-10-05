#import <CoreText/SFNTLayoutTypes.h>
#import "Core/PGCore.h"
#import "PGRTokens.h"
#import "PGRAccent.h"

const CGFloat PGRSideMargin = 16;
const CGFloat PGRGrid = 8;
const CGFloat PGRRadiusArtwork = 12;
const CGFloat PGRRadiusCard = 16;
const CGFloat PGRRadiusCover = 8;
const CGFloat PGRRadiusThumb = 6;
const CGFloat PGRGlassCircleSize = 44;
const CGFloat PGRActionHeight = 48;
const CGFloat PGRActionSpacing = 12;
const CGFloat PGRGlassSpacing = 16;
const NSTimeInterval PGRCrossfade = 0.35;

// A layout spring settles in about this long without overshooting; a press gives a little back.
static const NSTimeInterval kLayoutDuration = 0.45, kPressDuration = 0.32;
static const CGFloat kPressDamping = 0.62;

UIColor *PGRPrimary(void) {
    return UIColor.whiteColor;
}

UIColor *PGRSecondary(void) {
    return [UIColor colorWithWhite:1 alpha:PGRIncreaseContrast() ? 0.80 : 0.65];
}

UIColor *PGRTertiary(void) {
    return [UIColor colorWithWhite:1 alpha:PGRIncreaseContrast() ? 0.60 : 0.40];
}

// Read per call: the accent is stored as it is picked, and the colour row reads it the same way.
UIColor *PGRAccent(void) {
    return PGRAccentColor() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
}

UIColor *PGRNeutralField(void) {
    return [UIColor colorWithRed:0x12 / 255.0 green:0x12 / 255.0 blue:0x12 / 255.0 alpha:1];
}

UIColor *PGRSolidGlassFill(void) {
    return [UIColor colorWithWhite:1 alpha:0.16];
}

UIColor *PGRHairline(void) {
    return [UIColor colorWithWhite:1 alpha:PGRIncreaseContrast() ? 0.20 : 0.12];
}

UIColor *PGRElevated(UIColor *field) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![field getRed:&r green:&g blue:&b alpha:&a]) return [UIColor colorWithWhite:1 alpha:0.08];
    // 12% towards white keeps a card on a black field clear of the greys PGRAmoled.x turns black.
    CGFloat lift = 0.12;
    return [UIColor colorWithRed:r + (1 - r) * lift green:g + (1 - g) * lift blue:b + (1 - b) * lift alpha:1];
}

UIFont *PGRFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    UIContentSizeCategory current = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (largest && UIContentSizeCategoryCompareToCategory(current, largest) == NSOrderedDescending) current = largest;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:current];
    CGFloat size = [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits].pointSize;
    return [UIFont systemFontOfSize:size weight:weight];
}

UIFont *PGRMonospacedDigitsFont(UIFont *font) {
    if (!font) return nil;
    NSArray *features = @[@{UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType), UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}];
    UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute: features}];
    return [UIFont fontWithDescriptor:descriptor size:font.pointSize];
}

BOOL PGRReduceMotion(void) {
    return UIAccessibilityIsReduceMotionEnabled();
}

BOOL PGRReduceTransparency(void) {
    return UIAccessibilityIsReduceTransparencyEnabled();
}

BOOL PGRIncreaseContrast(void) {
    return UIAccessibilityDarkerSystemColorsEnabled();
}

void PGRAnimate(PGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    if (!animations) return;
    if (motion != PGRMotionFade && PGRReduceMotion()) {
        [UIView performWithoutAnimation:animations];
        if (completion) completion(YES);
        return;
    }
    UIViewAnimationOptions options = UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;
    switch (motion) {
        case PGRMotionLayout:
            [UIView animateWithDuration:kLayoutDuration delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case PGRMotionPress:
            [UIView animateWithDuration:kPressDuration delay:0 usingSpringWithDamping:kPressDamping initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case PGRMotionFade:
            [UIView animateWithDuration:PGRCrossfade delay:0 options:options | UIViewAnimationOptionCurveEaseInOut animations:animations completion:completion];
            break;
    }
}
