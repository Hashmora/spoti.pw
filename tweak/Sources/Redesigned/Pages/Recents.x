// Recents, the listening history: the redesign's bar over the list (Pages/PageBar.m), its chips on glass, and the
// list run under the bars.
//
// Tree (trees/continuous/7.txt:19-41): the page is a plain view holding an Encore StackView {0, 91} 390x598 -- the
// bar's bottom to the top of what the tab bar and the now playing bar take -- of the chips (Podcasts, Music: the
// same Encore ChipView and PillView as Liked Songs', Kit/SGRChips.h) and the list, a UICollectionView on
// #000000. The list stopped where the stack did, so its rows were cut off short of the bar above and the bars
// below, leaving a black margin at either end, where every other redesigned list runs on under glass.
//
// So the stack is made as tall as the page and the list as tall as the stack, and the two margins go to the list
// as insets: its first row starts where it did, below the chips, and the last one clears the bars. The chips are
// moved down by the margin they stood under, by a transform, which the stack's layout never writes, and kept
// over the rows that scroll under them. The frames are set again after every pass of the view the stack stands in
// and of the stack, since Spotify's constraints and the stack's layout put them back at the bar's edge.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kInsetKey, kWatchedKey, kListKey;

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

static void extend(UIView *page, UICollectionView *list) {
    UIView *stack = list.superview;
    UIView *host = stack.superview;
    UIView *chips = chipsBesides(list);
    if (!host || !chips) return;
    CGFloat top = page.safeAreaInsets.top, bottom = page.safeAreaInsets.bottom;

    CGRect frame = host.bounds;
    if (!CGRectEqualToRect(stack.frame, frame)) stack.frame = frame;
    if (stack.clipsToBounds) stack.clipsToBounds = NO;

    // The chips down by the margin they stood under, and over the list, which is as tall as the stack and whose
    // rows scroll up beneath them. Last among the stack's views so they still take their touches.
    CGAffineTransform down = CGAffineTransformMakeTranslation(0, top);
    if (!CGAffineTransformEqualToTransform(chips.transform, down)) chips.transform = down;
    if (stack.subviews.lastObject != chips) [stack bringSubviewToFront:chips];
    CGRect listFrame = stack.bounds;
    if (!CGRectEqualToRect(list.frame, listFrame)) list.frame = listFrame;
    if (list.clipsToBounds) list.clipsToBounds = NO;

    // The margins go to the list as insets, the first row where it was, below the chips, and no safe area of
    // its own on top of them.
    if (list.contentInsetAdjustmentBehavior != UIScrollViewContentInsetAdjustmentNever) list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    UIEdgeInsets inset = UIEdgeInsetsMake(top + chips.bounds.size.height, 0, bottom, 0);
    if (fabs(list.contentInset.top - inset.top) < 0.5 && fabs(list.contentInset.bottom - inset.bottom) < 0.5) return;
    BOOL atTop = !objc_getAssociatedObject(list, &kInsetKey) || list.contentOffset.y <= -list.adjustedContentInset.top + 1;
    list.contentInset = inset;
    list.verticalScrollIndicatorInsets = inset;
    if (atTop) list.contentOffset = CGPointMake(list.contentOffset.x, -inset.top);
    objc_setAssociatedObject(list, &kInsetKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGLog(@"redesign recents: list under the bars, insets %.0f and %.0f, stack %@", inset.top, inset.bottom, NSStringFromCGRect(stack.frame));
}

static void dress(UIViewController *page) {
    SGRDressBarPage(page);
    UIView *view = page.viewIfLoaded;
    if (!view.window) return;
    UICollectionView *list = listIn(view);
    if (!list) return;
    SGRGlassChipsIn(chipsBesides(list));
    extend(view, list);
    // Spotify's constraints set the stack back after each pass of the view it is in, and the stack sets the list
    // back after each pass of its own.
    for (UIView *watched in @[list.superview.superview ?: view, list.superview]) {
        if (objc_getAssociatedObject(watched, &kWatchedKey)) continue;
        __weak UIViewController *weakPage = page;
        if (SGRObserveLayout(watched, ^(UIView *laidOut) {
                UIViewController *strong = weakPage;
                UICollectionView *found = strong ? listIn(strong.viewIfLoaded) : nil;
                if (found) extend(strong.viewIfLoaded, found);
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
        %init(SGRRecents, SGRRecentsController = page);
    } else {
        SGLog(@"class Recents_RecentsPageImpl.RecentsViewController not found, Recents keeps Spotify's bar");
    }
}
