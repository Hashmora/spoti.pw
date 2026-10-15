// Recents, the listening history: the redesign's bar over the list (Pages/PageBar.m), its chips on glass, and the
// list run under the bars at the top and the bottom.
//
// Tree (trees/continuous/8.txt): the page is a plain view holding an Encore StackView of the chips (Podcasts, Music:
// the same Encore ChipView and PillView as Liked Songs', Kit/SGRChips.h) and the list, a UICollectionView on
// #000000, in that order. The stack starts at the bar's bottom and stopped where the tab bar and the now playing bar
// begin, so the last rows were cut off short of them, leaving a black margin where every other redesigned list runs
// on under glass.
//
// So the stack is made as tall as the page from where it starts, and what the bars below took of the stack goes to
// the list as its bottom inset: the last row clears them. The chips stay first in the stack, where Spotify put
// them. Bringing them to the front put them at the bottom of the page, since the stack arranges its views in order
// (trees/continuous/8.txt). The frames are set again after every pass of the view the stack stands in and of the
// stack, since Spotify's constraints and the stack's layout put them back.
//
// The list began where the chips end and clipped there, so rows scrolled up and were cut off in a straight line
// under the chips, leaving a black band over the top of the page (trees/continuous/4.txt: the list {0, 52} in a stack
// at y=91). Now the list is as tall as the whole page, from its top edge, with the bar and the chips as its top
// inset, so rows run on up under the glass chips and the title as they do in the library. The chips are drawn
// above the list by their layer's zPosition (their place in the stack is untouched), and the list gives up the
// touches that fall on the chips, which it would otherwise take, being over them.
//
// The chips of a filter that has just been picked (Clear filter, Saved, Played, trees/continuous/5.txt, 6.txt) are made
// by Spotify after the page's own layout, which never met them, so they stayed flat grey. The row they are made
// in is watched for its own layout, and every chip in it is dressed as it comes.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kInsetKey, kWatchedKey, kListKey, kOwnFrameKey, kTakenKey, kHeaderKey, kChipsWatchedKey;

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

    // The list from the top edge of the page to its bottom, over the chips; they are drawn above it.
    CGFloat barBottom = frame.origin.y;
    CGFloat under = CGRectGetMaxY(chips.frame);
    CGRect listFrame = CGRectMake(0, -barBottom, stack.bounds.size.width, pageHeight);
    if (listFrame.size.height > 0 && !CGRectEqualToRect(list.frame, listFrame)) list.frame = listFrame;
    if (stack.clipsToBounds) stack.clipsToBounds = NO;
    if (chips.layer.zPosition != 1) chips.layer.zPosition = 1;
    // Where the list gives its touches up to the chips, in the stack's coordinates.
    NSNumber *zone = objc_getAssociatedObject(list, &kHeaderKey);
    if (!zone || fabs(zone.doubleValue - under) > 0.5) {
        objc_setAssociatedObject(list, &kHeaderKey, @(under), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // The bar and the chips are the list's top inset, the bars below its bottom inset, with no safe area of its
    // own on top of either.
    if (list.contentInsetAdjustmentBehavior != UIScrollViewContentInsetAdjustmentNever) list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    UIEdgeInsets inset = UIEdgeInsetsMake(barBottom + under, 0, MAX(taken, page.safeAreaInsets.bottom), 0);
    UIEdgeInsets old = list.contentInset;
    BOOL moving = list.isDragging || list.isDecelerating;
    if (fabs(old.bottom - inset.bottom) < 0.5 && fabs(old.top - inset.top) < 0.5) {
        // A reload of the rows can send the list back to offset 0, which is the first row under the chips.
        if (!moving && inset.top > 0 && fabs(list.contentOffset.y) < 0.5) list.contentOffset = CGPointMake(0, -inset.top);
        return;
    }
    BOOL atTop = list.contentOffset.y <= -old.top + 1;
    list.contentInset = inset;
    list.verticalScrollIndicatorInsets = inset;
    if (atTop && !moving) list.contentOffset = CGPointMake(0, -inset.top);
    objc_setAssociatedObject(list, &kInsetKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGLog(@"redesign recents: list under the bars, inset top %.0f bottom %.0f, stack %@", inset.top, inset.bottom, NSStringFromCGRect(stack.frame));
}

// The row of chips scrolls inside the chips view: the chips of a filter just picked are put there after the page's
// own layout, so the scroll view is watched, and every chip in it is dressed (a chip already dressed is left be).
static UIScrollView *chipsScrollIn(UIView *chips) {
    __block UIScrollView *found = nil;
    SGForEachView(chips, ^(UIView *v) {
        if (!found && [v isKindOfClass:UIScrollView.class]) found = (UIScrollView *)v;
    });
    return found;
}

static void watchChips(UIView *chips) {
    UIScrollView *scroll = chipsScrollIn(chips);
    if (!scroll || objc_getAssociatedObject(scroll, &kChipsWatchedKey)) return;
    if (SGRObserveLayout(scroll, ^(UIView *laidOut) { SGRGlassChipsIn(laidOut); })) {
        objc_setAssociatedObject(scroll, &kChipsWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void dress(UIViewController *page) {
    SGRDressBarPage(page);
    UIView *view = page.viewIfLoaded;
    if (!view.window) return;
    UICollectionView *list = listIn(view);
    if (!list) return;
    UIView *chips = chipsBesides(list);
    SGRGlassChipsIn(chips);
    watchChips(chips);
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
// The list is over the chips, so the touches that fall on them are not its: it is not hit there. Only the list of
// this page carries kHeaderKey.
%hook UICollectionView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    NSNumber *zone = objc_getAssociatedObject(self, &kHeaderKey);
    if (zone) {
        UIView *list = (UIView *)self;
        if (list.superview && [list convertPoint:point toView:list.superview].y < zone.doubleValue) return NO;
    }
    return %orig;
}
%end

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
