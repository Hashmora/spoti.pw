// Redesign: the Add account circle of Who's listening on glass.
//
//   Who's listening   AccountSwitching_AccountPickerImpl.AccountPickerAddAccountTableViewCell (trees/continuous/5.txt):
//                     the 64pt circle at the head of the row, a plain UIView filled white at 7%, with the plus drawn
//                     over it by a sibling SPTEncoreIconView. The fill goes and a glass circle takes its place inside
//                     it; the plus stays above, since it comes after the circle in the cell's content view.
//
// Nothing clips the circle: it is a plain view with a corner radius and no mask, in a content view that does not clip
// either (the table's own clip is the screen's). The accounts' avatars are not touched: they are photographs and
// initials on colour, not controls drawn as a fill.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Pages/Pages.h"

static char kAddGlassKey;

static BOOL isFaintWhite(CGColorRef color) {
    if (!color || CGColorGetAlpha(color) > 0.3) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    for (size_t i = 0; i + 1 < n; i++) if (c[i] < 0.9) return NO;
    return n >= 2;
}

static void dressAdd(UITableViewCell *cell) {
    for (UIView *view in cell.contentView.subviews) {
        if (![view isMemberOfClass:UIView.class]) continue;
        CGSize size = view.bounds.size;
        if (fabs(size.width - size.height) > 0.5 || size.width < 40 || size.width > 80) continue;
        if (!isFaintWhite(view.layer.backgroundColor) && !objc_getAssociatedObject(view, &kAddGlassKey)) continue;
        if (view.backgroundColor && ![view.backgroundColor isEqual:UIColor.clearColor]) view.backgroundColor = UIColor.clearColor;
        if (view.layer.backgroundColor) view.layer.backgroundColor = NULL;
        SGRGlassInside(view, &kAddGlassKey, size.width);
    }
}

%group SGRAccountPickerGlass
%hook SGRAddAccountCell
- (void)layoutSubviews {
    %orig;
    dressAdd((UITableViewCell *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    Class cell = SGRPageClass(@"AccountSwitching_AccountPickerImpl", @"AccountPickerAddAccountTableViewCell");
    if (cell) {
        %init(SGRAccountPickerGlass, SGRAddAccountCell = cell);
    } else {
        SGLog(@"class AccountSwitching_AccountPickerImpl.AccountPickerAddAccountTableViewCell not found, Who's listening keeps Spotify's Add account circle");
    }
}
