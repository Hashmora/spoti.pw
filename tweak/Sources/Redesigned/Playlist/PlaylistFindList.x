// Redesign: the list under "Find on this page" (Liked Songs and any other playlist) runs on under the bars.
//
// Tree (trees/continuous/2.txt): the page (ListUXPlatform_FreeTierPlaylistImpl.FTPSearchViewController) is a plain view on
// #000000 holding one UICollectionView, id=SPTFreeTierPlaylistSearchTableView, which Spotify makes 689pt tall on an 844pt
// page: it stops where the now playing bar begins. Under the glass tab bar and the glass now playing bar that left a
// black slab the page shows through, a backing behind the bars, where every other redesigned list runs on beneath
// them and shows through the glass.
//
// So the list is made as tall as the page, and what Spotify took off its foot goes to the list as its bottom inset: the
// last row still clears the bars. The top stays Spotify's own (the bar's height, from the safe area), read once and set
// as an inset so that dropping the automatic adjustment, which would add the bars' safe area to the bottom twice,
// leaves the top where it was. The frame is set again after each pass of the page, since Spotify's constraints
// put it back (the same as Pages/Recents.x).
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Pages/Pages.h"

static char kListKey, kWatchedKey, kOwnFrameKey, kTakenKey, kTopKey;

static UICollectionView *findListIn(UIView *view) {
    UICollectionView *cached = objc_getAssociatedObject(view, &kListKey);
    if (cached && [cached isDescendantOfView:view]) return cached;
    __block UICollectionView *list = nil;
    SGForEachView(view, ^(UIView *v) {
        if (list || ![v isKindOfClass:UICollectionView.class]) return;
        if ([v.accessibilityIdentifier isEqualToString:@"SPTFreeTierPlaylistSearchTableView"]) list = (UICollectionView *)v;
    });
    if (list) objc_setAssociatedObject(view, &kListKey, list, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return list;
}

static void extendFindList(UIView *page, UICollectionView *list) {
    if (!page.window || list.superview != page) return;
    CGFloat pageHeight = page.bounds.size.height;
    if (pageHeight < 1 || list.bounds.size.width < 1) return;

    // What Spotify took off the list's foot: read while the list is in the frame Spotify gave it, not ours.
    NSValue *own = objc_getAssociatedObject(list, &kOwnFrameKey);
    if (!own || !CGRectEqualToRect(own.CGRectValue, list.frame)) {
        objc_setAssociatedObject(list, &kTakenKey, @(MAX(pageHeight - CGRectGetMaxY(list.frame), 0)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat taken = [objc_getAssociatedObject(list, &kTakenKey) doubleValue];

    // The top as Spotify had it, before the automatic adjustment goes.
    NSNumber *top = objc_getAssociatedObject(list, &kTopKey);
    if (!top) {
        if (list.contentInsetAdjustmentBehavior == UIScrollViewContentInsetAdjustmentNever) return;
        CGFloat adjusted = list.adjustedContentInset.top;
        if (adjusted < 1) return;
        top = @(adjusted - list.contentInset.top);
        objc_setAssociatedObject(list, &kTopKey, top, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGRect wanted = CGRectMake(list.frame.origin.x, list.frame.origin.y, list.frame.size.width, pageHeight - list.frame.origin.y);
    if (!CGRectEqualToRect(list.frame, wanted)) list.frame = wanted;
    objc_setAssociatedObject(list, &kOwnFrameKey, [NSValue valueWithCGRect:list.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (list.contentInsetAdjustmentBehavior != UIScrollViewContentInsetAdjustmentNever) {
        list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    UIEdgeInsets inset = UIEdgeInsetsMake(top.doubleValue, 0, MAX(taken, page.safeAreaInsets.bottom), 0);
    UIEdgeInsets old = list.contentInset;
    if (fabs(old.top - inset.top) < 0.5 && fabs(old.bottom - inset.bottom) < 0.5) return;
    BOOL atTop = list.contentOffset.y <= -old.top + 1;
    list.contentInset = inset;
    list.verticalScrollIndicatorInsets = inset;
    if (atTop && !(list.isDragging || list.isDecelerating)) list.contentOffset = CGPointMake(0, -inset.top);
    SGLog(@"redesign find on page: list under the bars, inset top %.0f bottom %.0f, frame %@", inset.top, inset.bottom,
          NSStringFromCGRect(list.frame));
}

static void dress(UIViewController *controller) {
    UIView *page = controller.viewIfLoaded;
    if (!page.window) return;
    UICollectionView *list = findListIn(page);
    if (!list) return;
    extendFindList(page, list);
    if (!objc_getAssociatedObject(page, &kWatchedKey)) {
        __weak UIViewController *weak = controller;
        if (SGRObserveLayout(page, ^(UIView *laidOut) {
                UIViewController *strong = weak;
                UICollectionView *found = strong ? findListIn(laidOut) : nil;
                if (found) extendFindList(laidOut, found);
            })) {
            objc_setAssociatedObject(page, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

%ctor {
    if (!SGRedesignedUI() || !SGBelowiOS26()) return;
    // The list is sized by Spotify's constraints after the first layout.
    SGRPassSwiftController(@"ListUXPlatform_FreeTierPlaylistImpl", @"FTPSearchViewController", ^(UIViewController *c) { dress(c); });
}
