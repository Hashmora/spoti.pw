// Redesign, iOS < 26: the plus of "Add account" on glass, in both lists of accounts Spotify has.
//
// Tree (trees/continuous/4.txt:1102-1110): the left menu's list of accounts (AccountSwitching_AccountSwitchingUIImpl.
// AddAccountCell, 72x79) holds a plain UIView 48x48 bg=#FFFFFF@0.07 r=24 and, after it, the SPTEncoreIconView that draws the
// plus. The page the app shows after signing out of an account, "Who's listening?" (trees/continuous/5.txt:15-18,
// AccountSwitching_AccountPickerImpl.AccountPickerAddAccountTableViewCell, a table row), has the same two views at 64x64
// r=32 bg=#FFFFFF@0.07, beside the "Add account" label.
//
// The grey disc goes and a glass disc stands in it, with the faint white film the redesign's floating controls carry
// (the disc was a 7% white plate; plain glass over the list's black would read as nothing). The icon above it is
// Spotify's and is left alone. Spotify paints the disc again as the row is selected, highlighted or reused, so the fill is
// held clear (SGRHoldClear) and the row dresses it again from its own passes.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kDiscKey, kGlassKey;

// The disc: the one square plain view in the row with nothing in it, 40 to 80pt across. Found once; once it holds the glass it has a
// subview, so it is known from the row afterwards, not by its look.
static UIView *plusDisc(UIView *row) {
    UIView *known = objc_getAssociatedObject(row, &kDiscKey);
    if (known && [known isDescendantOfView:row]) return known;
    __block UIView *found = nil;
    SGForEachView(row, ^(UIView *view) {
        if (found || view == row || ![view isMemberOfClass:UIView.class] || view.subviews.count) return;
        CGSize size = view.bounds.size;
        if (size.width < 40 || size.width > 80 || fabs(size.width - size.height) > 0.5) return;
        found = view;
    });
    if (found) objc_setAssociatedObject(row, &kDiscKey, found, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return found;
}

static void dressPlus(UIView *row) {
    if (!row.window) return;
    UIView *disc = plusDisc(row);
    if (!disc || disc.bounds.size.width < 1 || disc.bounds.size.height < 1) return;
    SGRHoldClear(disc);
    SGRGlassFlatBoxFilm(disc, &kGlassKey);
}

%group SGRDrawerPlus
%hook SGRDrawerAddAccount
- (void)layoutSubviews {
    %orig;
    dressPlus((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    dressPlus((UIView *)self);
}
%end
%end

%group SGRPickerPlus
%hook SGRPickerAddAccount
- (void)layoutSubviews {
    %orig;
    dressPlus((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    dressPlus((UIView *)self);
}

// UIKit takes the fills of a row's views off as it is highlighted or selected and puts them back after.
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    %orig;
    dressPlus((UIView *)self);
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    %orig;
    dressPlus((UIView *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class drawer = SGRPageClass(@"AccountSwitching_AccountSwitchingUIImpl", @"AddAccountCell");
    if (drawer) {
        %init(SGRDrawerPlus, SGRDrawerAddAccount = drawer);
    } else {
        SGLog(@"class AccountSwitching_AccountSwitchingUIImpl.AddAccountCell not found, the left menu's Add account keeps its grey plus");
    }
    Class picker = SGRPageClass(@"AccountSwitching_AccountPickerImpl", @"AccountPickerAddAccountTableViewCell");
    if (picker) {
        %init(SGRPickerPlus, SGRPickerAddAccount = picker);
    } else {
        SGLog(@"class AccountSwitching_AccountPickerImpl.AccountPickerAddAccountTableViewCell not found, Who's listening keeps its grey plus");
    }
}
