// Redesign: Spotify's own white pop-up dialogs, dressed as the redesign's system notification (SGRAlertScreen.m): a
// glass card with 35pt corners, white text, a capsule button filled with the accent for the main action and one of
// 10% white for the rest.
//
//   Get smoother transitions     trees/continuous/8.txt:1731   id=PopUp.Dialog, white r=8
//   Discard changes?             trees/continuous/9.txt:1805   id=PopUp.Dialog
//   Make this playlist private?  trees/continuous/10.txt:1253  id=PopUp.Dialog
//   Update preferred location    trees/continuous/12.txt:472   id=PopUpConfirmationDialog, a grey r=16 card with
//                                                              the Cancel button under it, in a window of its own
//
// Each lives in a UIWindow of level 1000 over a 54% black dim, and is not a UIAlertController, so SGRAlertHook.x never
// sees it. Spotify's views and buttons stay: only their paint is replaced, so every tap still reaches Spotify's own
// handler. The Encore buttons are told apart by their identifiers (Components.UI.PrimaryButton, ...TertiaryButton).
// Spotify lays the dialog out after it is attached, so the pass runs again a moment later.
//
// Create cover art > Cancel > "Are you sure" (trees/continuous/11.txt) is a web page, not a view of Spotify's: nothing to dress.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static const CGFloat kDialogRadius = 35;

static char kGlassKey, kFillKey;

static BOOL isButton(UIView *view) {
    NSString *ident = view.accessibilityIdentifier;
    return [ident isEqualToString:@"Components.UI.PrimaryButton"] || [ident isEqualToString:@"Components.UI.TertiaryButton"];
}

static BOOL insideButton(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) {
        if (isButton(v)) return YES;
    }
    return NO;
}

// Black or white, whichever reads on the accent.
static UIColor *onAccent(UIColor *accent) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![accent getRed:&r green:&g blue:&b alpha:&a]) return UIColor.whiteColor;
    return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6 ? UIColor.blackColor : UIColor.whiteColor;
}

static void dressButton(UIView *button) {
    CGSize size = button.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    BOOL primary = [button.accessibilityIdentifier isEqualToString:@"Components.UI.PrimaryButton"];
    UIView *fill = objc_getAssociatedObject(button, &kFillKey);
    if (!fill) {
        fill = [UIView new];
        fill.userInteractionEnabled = NO;
        fill.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(button, &kFillKey, fill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button insertSubview:fill atIndex:0];
    }
    if (button.subviews.firstObject != fill) [button sendSubviewToBack:fill];
    fill.frame = button.bounds;
    fill.layer.cornerRadius = size.height / 2;
    UIColor *accent = SGRAccent();
    fill.backgroundColor = primary ? accent : [UIColor colorWithWhite:1 alpha:0.1];
    UIColor *text = primary ? onAccent(accent) : UIColor.whiteColor;
    SGForEachView(button, ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).textColor != text) ((UILabel *)view).textColor = text;
    });
}

// Spotify's paint (the white card, the grey one, an image's placeholder) goes; the glass and the buttons' fills stay.
static void clearPaint(UIView *view, UIView *glass, int depth) {
    if (depth > 12 || view == glass || isButton(view)) return;
    CGColorRef paint = view.layer.backgroundColor;
    if (paint && CGColorGetAlpha(paint) > 0.05) view.backgroundColor = UIColor.clearColor;
    if (view.layer.cornerRadius > 0 && depth > 0) view.layer.cornerRadius = 0;
    for (UIView *sub in view.subviews) clearPaint(sub, glass, depth + 1);
}

// Update preferred location: the dialog's stack holds the card's content (the text and Confirm, 24pt of air under
// Confirm) and then Cancel after 16pt more, flush with the bottom edge of the dialog (trees/continuous/3.txt: Confirm
// ends at 258.7, Cancel runs 298.7 to 346.7 in a 346.7 card). Cancel moves up to kCancelGap under Confirm, and the
// room that frees goes under it as the stack's bottom margin, so the card keeps its height and Cancel keeps its air.
// The spacing and the margin are properties of the stack, so Spotify's own layout keeps them.
static const CGFloat kCancelGap = 12, kCancelBottom = 28;
static char kCancelUnderKey;

static void spaceCancel(UIView *host) {
    UIStackView *stack = nil;
    for (UIView *view in host.subviews) {
        if ([view isKindOfClass:UIStackView.class] && [view.accessibilityIdentifier isEqualToString:@"PopUpConfirmationDialog"]) stack = (UIStackView *)view;
    }
    if (!stack || stack.arrangedSubviews.count != 2) return;
    UIView *card = stack.arrangedSubviews.firstObject, *cancel = stack.arrangedSubviews.lastObject;
    if (![cancel.accessibilityIdentifier isEqualToString:@"Components.UI.TertiaryButton"]) return;
    // The air under Confirm in the card, read once: it is what the stack's spacing is measured against, and reading it
    // again after the spacing has changed the card's height would chase its own tail.
    NSNumber *under = objc_getAssociatedObject(stack, &kCancelUnderKey);
    if (!under) {
        UIView *confirm = nil;
        for (UIView *sub in card.subviews) {
            if ([sub.accessibilityIdentifier isEqualToString:@"Components.UI.PrimaryButton"]) confirm = sub;
        }
        if (!confirm || card.bounds.size.height < 1 || confirm.bounds.size.height < 1) return;
        under = @(MAX(0, card.bounds.size.height - CGRectGetMaxY(confirm.frame)));
        objc_setAssociatedObject(stack, &kCancelUnderKey, under, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat custom = kCancelGap - under.doubleValue;
    if (fabs([stack customSpacingAfterView:card] - custom) > 0.5) [stack setCustomSpacing:custom afterView:card];
    // Written whole: a stack's margins are 8pt on every side by default, and they apply once the arrangement follows them.
    UIEdgeInsets margins = UIEdgeInsetsMake(0, 0, kCancelBottom, 0);
    if (stack.insetsLayoutMarginsFromSafeArea) stack.insetsLayoutMarginsFromSafeArea = NO;
    if (!UIEdgeInsetsEqualToEdgeInsets(stack.layoutMargins, margins)) stack.layoutMargins = margins;
    if (!stack.layoutMarginsRelativeArrangement) stack.layoutMarginsRelativeArrangement = YES;
}

static void dressDialog(UIView *host) {
    if (host.bounds.size.width < 1 || host.bounds.size.height < 1) return;
    UIView *glass = SGGlassFor(host, &kGlassKey);
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (!CGRectEqualToRect(glass.frame, host.bounds)) glass.frame = host.bounds;
    SGShapeGlass(glass, kDialogRadius, NO);
    SGRThickenSheetGlass(glass, kDialogRadius);
    if (!SGRReduceTransparency()) SGRDimSheetGlass(glass, 0.45);

    clearPaint(host, glass, 0);
    spaceCancel(host);
    host.layer.cornerRadius = kDialogRadius;
    host.layer.cornerCurve = kCACornerCurveContinuous;
    BOOL clip = !SGUseLegacyGlass();
    if (host.layer.masksToBounds != clip) host.layer.masksToBounds = clip;

    SGForEachView(host, ^(UIView *view) {
        if (isButton(view)) {
            dressButton(view);
            return;
        }
        if (![view isKindOfClass:UILabel.class] || insideButton(view, host) || SGIsInside(view, glass)) return;
        UILabel *label = (UILabel *)view;
        UIColor *color = label.font.pointSize >= 17 ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.7];
        label.textColor = color;
    });
}

// The view that carries the card: the white ScrollView itself, or for the location dialog the element view that holds the card and Cancel.
static UIView *hostOf(UIView *view) {
    NSString *ident = view.accessibilityIdentifier;
    if ([ident isEqualToString:@"PopUp.Dialog"]) return view;
    if ([ident isEqualToString:@"PopUpConfirmationDialog"]) {
        UIView *parent = view.superview;
        return parent && CGSizeEqualToSize(parent.bounds.size, view.bounds.size) ? parent : view;
    }
    return nil;
}

%hook UIView
- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    if (!view.window || !view.accessibilityIdentifier.length) return;
    UIView *host = hostOf(view);
    if (!host) return;
    __weak UIView *weak = host;
    for (NSNumber *wait in @[@0.0, @0.1, @0.3]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *shown = weak;
            if (shown.window) dressDialog(shown);
        });
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
