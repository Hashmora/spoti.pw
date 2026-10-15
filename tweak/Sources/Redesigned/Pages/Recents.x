// Recents, the listening history: the redesign's bar over the list (Pages/PageBar.m), its chips on glass, and the
// list run under the bars at the bottom.
//
// Tree (trees/continuous/8.txt): the page is a plain view holding an Encore StackView of the chips (Podcasts, Music:
// the same Encore ChipView and PillView as Liked Songs', Kit/SGRChips.h) and the list, a UICollectionView on
// #000000, in that order. The stack starts at the bar's bottom and stopped where the tab bar and the now playing bar
// begin, so the last rows were cut off short of them, leaving a black margin where every other redesigned list runs
// on under glass.
//
// So the stack is made as tall as the page from where it starts, the list as tall as what is left of the stack under
// the chips, and what the bars below took of the stack goes to the list as its bottom inset: the last row clears
// them. The chips stay first in the stack, where Spotify put them. Bringing them to the front put them at the
// bottom of the page, since the stack arranges its views in order (trees/continuous/8.txt), and a transform is not
// what they need either: the list begins under them. The frames are set again after every pass of the view the
// stack stands in and of the stack, since Spotify's constraints and the stack's layout put them back.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kInsetKey, kWatchedKey, kListKey, kOwnFrameKey, kTakenKey;

// The page's list, found once: the one collection view as wide as the page.
static UICollectionView *listIn(UIView *view) {
    UICollectionView *cached = objc_getAssociatedObject(view, &kListKey);
    if (cached && [cached isDescendantOfView:view]) return cached;
    __block UICollectionView *list = nil;
    SGForEachView(view, ^(UIView *v) {
        if (!list && [v isKindOfClass:UICollectionView.class] && v.bounds.size.width >= view.bounds.size.width * 0.9) list = (UICollectionView *)v;
    });
    if (list) objc_setAssociatedObject(view, &kListKey, list, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return list;
}

// What shares the stack with the list: the row of chips.
static UIView *chipsBesides(UIView *list) {
    for (UIView *sub in list.superview.subviews) {
        if (sub != list) return sub;
    }
    return nil;
}

static void extendRecentsList(UIView *page, UICollectionView *list) {
    UIView *stack = list.superview;
    UIView *host = stack.superview;
    UIView *chips = chipsBesides(list);
    if (!host || !chips) return;
    CGFloat pageHeight = host.bounds.size.height;

    // What the bars below take of the page is read off the stack as Spotify's constraints leave it: whenever it is
    // not in the frame this pass put it in. Left alone while it is, so what was read stays.
    NSValue *own = objc_getAssociatedObject(stack, &kOwnFrameKey);
    CGRect frame = stack.frame;
    if (!own || !CGRectEqualToRect(own.CGRectValue, frame)) {
        objc_setAssociatedObject(stack, &kTakenKey, @(MAX(pageHeight - CGRectGetMaxY(frame), 0)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat taken = [objc_getAssociatedObject(stack, &kTakenKey) doubleValue];

    CGRect wanted = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width, pageHeight - frame.origin.y);
    if (!CGRectEqualToRect(stack.frame, wanted)) stack.frame = wanted;
    objc_setAssociatedObject(stack, &kOwnFrameKey, [NSValue valueWithCGRect:stack.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // The list under the chips, down to the bottom of the stack, which is the bottom of the page.
    CGFloat under = CGRectGetMaxY(chips.frame);
    CGRect listFrame = CGRectMake(0, under, stack.bounds.size.width, stack.bounds.size.height - under);
    if (listFrame.size.height > 0 && !CGRectEqualToRect(list.frame, listFrame)) list.frame = listFrame;
    if (stack.clipsToBounds) stack.clipsToBounds = NO;

    // The bars below go to the list as its inset, with no safe area of its own on top of it.
    if (list.contentInsetAdjustmentBehavior != UIScrollViewContentInsetAdjustmentNever) list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    UIEdgeInsets inset = UIEdgeInsetsMake(0, 0, MAX(taken, page.safeAreaInsets.bottom), 0);
    if (fabs(list.contentInset.bottom - inset.bottom) < 0.5 && fabs(list.contentInset.top) < 0.5) return;
    list.contentInset = inset;
    list.verticalScrollIndicatorInsets = inset;
    objc_setAssociatedObject(list, &kInsetKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGLog(@"redesign recents: list under the bars, bottom inset %.0f, stack %@", inset.bottom, NSStringFromCGRect(stack.frame));
}

static void dress(UIViewController *page) {
    SGRDressBarPage(page);
    UIView *view = page.viewIfLoaded;
    if (!view.window) return;
    UICollectionView *list = listIn(view);
    if (!list) return;
    SGRGlassChipsIn(chipsBesides(list));
    extendRecentsList(view, list);
    // Spotify's constraints set the stack back after each pass of the view it is in, and the stack sets the list
    // back after each pass of its own.
    for (UIView *watched in @[list.superview.superview ?: view, list.superview]) {
        if (objc_getAssociatedObject(watched, &kWatchedKey)) continue;
        __weak UIViewController *weakPage = page;
        if (SGRObserveLayout(watched, ^(UIView *laidOut) {
                UIViewController *strong = weakPage;
                UICollectionView *found = strong ? listIn(strong.viewIfLoaded) : nil;
                if (found) extendRecentsList(strong.viewIfLoaded, found);
            })) {
            objc_setAssociatedObject(watched, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

%group SGRRecents
%hook SGRRecentsController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dress((UIViewController *)self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    dress((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // The bar's buttons, the chips and the rows are made after the first layout.
    __weak UIViewController *weak = (UIViewController *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weak) dress(weak);
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    SGRUndressBarPage((UIViewController *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class page = SGRPageClass(@"Recents_RecentsPageImpl", @"RecentsViewController");
    if (page) {
        SGRRegisterBarPages(^BOOL(UIViewController *top) { return [top isKindOfClass:page]; });
        %init(SGRRecents, SGRRecentsController = page);
    } else {
        SGLog(@"class Recents_RecentsPageImpl.RecentsViewController not found, Recents keeps Spotify's bar");
    }
}
