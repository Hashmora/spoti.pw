// Live Events, the concerts hub (LiveEvents_LiveEventsPageImpl.LiveEventsPageViewController): the header's title and
// buttons on glass over the header's own gradient, and the list run on under the tab bar.
//
// Tree (trees/continuous/23.txt): the page is a plain view holding the list (LiveEventsPage.ContentScrollView, a
// UICollectionView on #000000) and the header, a LegacyUI_ECMCoreKit.HeaderLayout (Components.UI.EventHeaderHubPage) with
// the gradient behind it and, in its foreground, the HeaderNavigationBar the playlist, album and artist pages have: its
// own GradientView, the name "Live Events" as a label, Back (Components.Header.UI.BackButton) and, in a stack at the
// trailing edge, Saved and Notifications (Encore Tertiary buttons, 48x48). The list was 689pt high, ending where the
// now playing bar begins, so under the glass tab bar there was the page's black instead of the last events.
//
// The header keeps its gradient. Its buttons are the page's pinned glass circles (Back at the leading corner,
// Notifications in the trailing one and Saved beside it), as on the playlist, album and artist pages: Spotify's own are
// concealed and fired by them, since a circle glassed in place fought the header's collapse. The name in the bar sits on
// the glass capsule those pages' bars give theirs (Playlist/PlaylistBar.x), here without taking the gradient off.
//
// The list is made as tall as the page, and what the bars below took of it goes to its bottom inset, so the last event
// clears them and the rows run on under the glass, as Recents' (Pages/Recents.x) do. Spotify's constraints put the frame
// back after each pass of the page's view, so it is set again after every one.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kListKey, kBellKey, kSavedKey, kBellPinKey, kSavedPinKey, kOwnFrameKey, kTakenKey, kWatchedKey, kTitleGlassKey;

// Side padding of the name inside its capsule, and its height: the same as every other page's (Pages/PageBar.m).
static const CGFloat kTitlePadding = 18, kTitleHeight = 44;

// Invisible whatever Spotify does to it: the layer hidden, and an empty mask for when Spotify shows it anyway. The control
// is still there to be fired.
static void conceal(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static UIScrollView *listIn(UIView *page) {
    UIView *list = SGRFindByIdentifier(page, @"LiveEventsPage.ContentScrollView", &kListKey);
    return [list isKindOfClass:UIScrollView.class] ? (UIScrollView *)list : nil;
}

static void extendList(UIScrollView *list) {
    UIView *host = list.superview;
    CGFloat pageHeight = host.bounds.size.height;
    CGRect frame = list.frame;
    if (pageHeight < 1 || frame.size.width < 1 || frame.size.height < pageHeight * 0.5) return;

    // What the bars below take of the page is read off the list as Spotify's constraints leave it: whenever it is not in
    // the frame this pass put it in. Left alone while it is, so what was read stays.
    NSValue *own = objc_getAssociatedObject(list, &kOwnFrameKey);
    if (!own || !CGRectEqualToRect(own.CGRectValue, frame)) {
        CGFloat taken = MAX(pageHeight - CGRectGetMaxY(frame), 0);
        objc_setAssociatedObject(list, &kTakenKey, @(MIN(taken, pageHeight * 0.4)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat taken = [objc_getAssociatedObject(list, &kTakenKey) doubleValue];

    CGRect wanted = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width, pageHeight - frame.origin.y);
    if (!CGRectEqualToRect(list.frame, wanted)) list.frame = wanted;
    objc_setAssociatedObject(list, &kOwnFrameKey, [NSValue valueWithCGRect:list.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // The list's own safe area at the bottom is counted again once it reaches the bottom edge, so it is taken off.
    CGFloat safe = list.contentInsetAdjustmentBehavior == UIScrollViewContentInsetAdjustmentNever ? 0 : list.safeAreaInsets.bottom;
    CGFloat bottom = MAX(taken - safe, 0);
    UIEdgeInsets inset = list.contentInset;
    if (fabs(inset.bottom - bottom) < 0.5) return;
    inset.bottom = bottom;
    list.contentInset = inset;
    UIEdgeInsets bar = list.verticalScrollIndicatorInsets;
    bar.bottom = bottom;
    list.verticalScrollIndicatorInsets = bar;
    SGLog(@"redesign live events: list under the bars, inset bottom %.0f, frame %@", bottom, NSStringFromCGRect(list.frame));
}

// The name in the header's bar: the SPTEncoreLabel directly under the HeaderNavigationBar that holds text (the Back
// button's is a glyph in a button of its own, deeper down). The capsule is its child, so it follows the label's alpha.
static void glassTitle(UIView *page) {
    static Class barClass;
    if (!barClass) barClass = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit19HeaderNavigationBar");
    if (!barClass) return;
    __block UIView *bar = nil;
    SGForEachView(page, ^(UIView *v) {
        if (!bar && [v isKindOfClass:barClass]) bar = v;
    });
    for (UIView *sub in bar.subviews) {
        if (![NSStringFromClass(sub.class) hasSuffix:@"EncoreLabel"]) continue;
        UILabel *text = nil;
        for (UIView *inner in sub.subviews) {
            if ([inner isKindOfClass:UILabel.class] && ((UILabel *)inner).text.length) text = (UILabel *)inner;
        }
        if (!text || sub.bounds.size.width < 1) continue;
        CGFloat wanted = ceil([text sizeThatFits:CGSizeMake(CGFLOAT_MAX, kTitleHeight)].width) + 2 * kTitlePadding;
        CGFloat width = MIN(MAX(wanted, kTitleHeight), sub.bounds.size.width);
        for (UIView *v = sub; v && v != page; v = v.superview) {
            if (v.clipsToBounds) v.clipsToBounds = NO;
        }
        SGRGlassCapsuleInside(sub, &kTitleGlassKey, CGSizeMake(width, kTitleHeight), NO);
        return;
    }
}

static void dress(UIViewController *controller) {
    UIView *view = controller.viewIfLoaded;
    if (!view.window || view.bounds.size.width < 1) return;

    static UIImage *heart, *bell;
    if (!heart) heart = [UIImage systemImageNamed:@"heart"];
    if (!bell) bell = [UIImage systemImageNamed:@"bell"];
    // Back is found under the page (Components.Header.UI.BackButton) and concealed by the pin.
    SGRPinnedBack(view, view);
    UIView *notifications = SGRFindByIdentifier(view, @"Components.UI.EventHeaderHubPage.Notifications", &kBellKey);
    UIView *saved = SGRFindByIdentifier(view, @"Components.UI.EventHeaderHubPage.Saved", &kSavedKey);
    conceal(notifications);
    conceal(saved);
    SGRPinnedTrailing(view, &kBellPinKey, notifications, 0, bell);
    SGRPinnedTrailing(view, &kSavedPinKey, saved, 1, heart);
    glassTitle(view);

    UIScrollView *list = listIn(view);
    if (!list) return;
    extendList(list);
    UIView *host = list.superview;
    if (host && !objc_getAssociatedObject(host, &kWatchedKey)) {
        __weak UIViewController *weakPage = controller;
        if (SGRObserveLayout(host, ^(UIView *laidOut) {
                UIViewController *strong = weakPage;
                UIScrollView *found = strong ? listIn(strong.viewIfLoaded) : nil;
                if (found) extendList(found);
            })) {
            objc_setAssociatedObject(host, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

%group SGRLiveEvents
%hook SGRLiveEventsController
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
    // The header's buttons and the list's rows are made after the first layout.
    __weak UIViewController *weak = (UIViewController *)self;
    for (NSNumber *delay in @[@0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) dress(weak);
        });
    }
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class page = SGRPageClass(@"LiveEvents_LiveEventsPageImpl", @"LiveEventsPageViewController");
    if (page) {
        %init(SGRLiveEvents, SGRLiveEventsController = page);
    } else {
        SGLog(@"class LiveEvents_LiveEventsPageImpl.LiveEventsPageViewController not found, Live Events keeps Spotify's header and list");
    }
}
