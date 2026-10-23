// Redesign, iOS < 26: the artist's and the album's list run under the glass header to the top of the screen. Both pages
// are CreativeWorkPlatform_TabsKit.PCFFTabLayoutViewController, which scrolls its header away and then pins the list's
// block 100pt (artist) or 104pt (album) down, where Spotify's own navigation bar ended: from there the list scrolls in a
// view that clips at that line, so under the redesign's glass Back, title and ⋯ the top of the page was the field's color
// with nothing passing under it, an opaque band the list was cut off against (the phone, 2026-10-23).
//
// How the page scrolls (the phone, 2026-10-23): the overlay scroll view (PCFFTabLayoutViewController.overlayScrollView)
// takes the finger; Spotify sets the container (.containerScrollView) to min(overlay, T) and the list in the block
// (.tabsViewAccessibilityID) to overlay - T, T being the header's height less the pinned band (584 - 100 = 484 on an
// artist). Here T is learnt the first time Spotify holds the container short of the overlay, and the block is let go to
// the very top: the container goes on to the block's own top, the list is set back by what the container went on, and
// the overlay's range grows by as much, so the list's end is still reached. At rest nothing moves.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "SGRRestyle.h"

static NSString *const kContainerID = @"PCFFTabLayoutViewController.containerScrollView";
static NSString *const kOverlayID = @"PCFFTabLayoutViewController.overlayScrollView";
static NSString *const kTabsID = @"PCFFTabLayoutViewController.tabsViewAccessibilityID";

// On the container: the pinned band learnt (NSNumber, 0 for none); the block. On the overlay: Spotify's own content height.
static char kLiftKey, kTabsKey, kRawHeightKey, kSetHeightKey;
static Class sListClass;

static UIScrollView *siblingWithID(UIView *view, NSString *ident) {
    for (UIView *sub in view.superview.subviews) {
        if ([sub isKindOfClass:UIScrollView.class] && [sub.accessibilityIdentifier isEqualToString:ident]) return (UIScrollView *)sub;
    }
    return nil;
}

// The block's top in the container's content: how far the container can go before the block reaches the screen's top.
static CGFloat blockTop(UIScrollView *container) {
    UIView *tabs = SGRFindByIdentifier(container, kTabsID, &kTabsKey);
    if (!tabs) return -1;
    return CGRectGetMinY(tabs.frame) + CGRectGetMinY(tabs.superview.frame);
}

static CGFloat liftOf(UIScrollView *container) {
    return [objc_getAssociatedObject(container, &kLiftKey) doubleValue];
}

static CGPoint containerOffset(UIScrollView *container, CGPoint offset) {
    // Without the list's class the list could not be set back, and it would jump by the lift.
    if (!sListClass) return offset;
    UIScrollView *overlay = siblingWithID(container, kOverlayID);
    CGFloat top = blockTop(container);
    if (!overlay || top <= 0) return offset;
    CGFloat finger = overlay.contentOffset.y;
    if (!objc_getAssociatedObject(container, &kLiftKey)) {
        // Spotify holding the container short of the overlay is the pin: what it holds it at is T.
        if (offset.y <= 0 || finger - offset.y < 0.5) return offset;
        CGFloat lift = top - offset.y;
        if (lift < 1 || lift > 300) lift = 0;
        objc_setAssociatedObject(container, &kLiftKey, @(lift), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign pinned tabs: the block was pinned %.0fpt down, it goes on to the top", lift);
        // The overlay's range, set before the lift was known, grows now.
        NSNumber *raw = objc_getAssociatedObject(overlay, &kRawHeightKey);
        if (raw && lift > 0) {
            objc_setAssociatedObject(overlay, &kSetHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            overlay.contentSize = CGSizeMake(overlay.contentSize.width, raw.doubleValue);
        }
    }
    if (liftOf(container) <= 0) return offset;
    offset.y = MIN(finger, top);
    return offset;
}

static UIScrollView *containerAbove(UIView *view) {
    int depth = 0;
    for (UIView *v = view.superview; v && depth < 12; v = v.superview, depth++) {
        if ([v isKindOfClass:UIScrollView.class] && [v.accessibilityIdentifier isEqualToString:kContainerID]) return (UIScrollView *)v;
    }
    return nil;
}

// How deep in a list's setContentOffset of ours this thread is. Should Spotify answer the list's scroll by setting the
// list again from inside it, that answer is passed through as it is, so no answer to an answer of ours can chain
// without end. The container's own offset is worked out from the overlay alone and is always set.
static __thread int sg_listDepth;

%hook UIScrollView
- (void)setContentOffset:(CGPoint)offset {
    UIScrollView *scroll = (UIScrollView *)self;
    NSString *ident = scroll.accessibilityIdentifier;
    if (ident && [ident isEqualToString:kContainerID]) {
        %orig(containerOffset(scroll, offset));
        return;
    }
    if (!sListClass || sg_listDepth > 0 || ![scroll isKindOfClass:sListClass]) {
        %orig(offset);
        return;
    }
    CGFloat lift = liftOf(containerAbove(scroll));
    if (lift <= 0) {
        %orig(offset);
        return;
    }
    offset.y = MAX(-scroll.adjustedContentInset.top, offset.y - lift);
    sg_listDepth++;
    %orig(offset);
    sg_listDepth--;
}

// Opening an artist's Show all crashed every time with this file on, 1.7 s of a main thread at work and then SIGSEGV,
// and never with it off (the phone, 2026-10-24): a size of the overlay's that Spotify works out from the size the
// overlay has, which was ours with the lift in it, came back each time a lift taller. A height that is the one this
// set last is Spotify's own echo of it, and goes through as it is, and nothing is added inside a set of ours.
static __thread int sg_sizeDepth;

- (void)setContentSize:(CGSize)size {
    UIScrollView *scroll = (UIScrollView *)self;
    NSString *ident = scroll.accessibilityIdentifier;
    if (sg_sizeDepth > 0 || !ident || ![ident isEqualToString:kOverlayID]) {
        %orig(size);
        return;
    }
    NSNumber *set = objc_getAssociatedObject(scroll, &kSetHeightKey);
    if (set && fabs(size.height - set.doubleValue) < 0.5) {
        %orig(size);
        return;
    }
    objc_setAssociatedObject(scroll, &kRawHeightKey, @(size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    size.height += MAX(0, liftOf(siblingWithID(scroll, kContainerID)));
    objc_setAssociatedObject(scroll, &kSetHeightKey, @(size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sg_sizeDepth++;
    %orig(size);
    sg_sizeDepth--;
}
%end

%ctor {
    if (!SGRedesignedUI() || !SGBelowiOS26()) return;
    // Off unless set (pref spotifyglass.redesign.pinnedTabs 1): with it on, an artist's Show all crashed every time and
    // with it off never (the phone, 2026-10-24, five tries), in a thread of Spotify's other than the main one, which the
    // sizes and offsets this file moves sent into a recursion. The list stops at Spotify's pinned band, as before.
    if (!SGHidden(@"spotifyglass.redesign.pinnedTabs")) return;
    sListClass = NSClassFromString(@"_TtC32CreativeWorkPlatform_TemplateKitP33_5F894CA2C02A3F3767683E90D6AA015014CollectionView");
    if (!sListClass) SGLog(@"redesign pinned tabs: CreativeWorkPlatform_TemplateKit's list class not found, the list keeps its pinned band");
    %init;
}
