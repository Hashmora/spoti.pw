// Song DNA's pages under SPNavigationBar, the redesign's bar over each (Pages/PageBar.m):
//
//   BlendViewController         the songs two people share, reached from a contributor's "view N songs together"
//   ArtistsDNAViewController    the contributors' page (trees/continuous/15.txt): the same bar (Back, Share and Close
//                               in the trailing stack, the Song DNA logo and its Beta tag as the title), which had
//                               none of the redesign. Its first row is a view above the list, not a row in it, so
//                               only the bar is dressed and the list is left as Spotify's
//
// Tree (trees/continuous/41.txt): a black page holding a radial gradient and the list from y=91, over it the navigation
// controller's blur (a plain 390x91 view with a UIVisualEffectView, #1C1C1C@0.73) and SPNavigationBar with Back, a
// trailing stack of Share (the Song DNA share button) and Close, and a title that is a picture, the Song DNA logo and
// its Beta tag, not a label. So the blur goes, Back, Share and Close are glass circles pinned to the corners (Close at
// the corner, Share beside it), and the logo sits on a glass capsule the way a name does on the playlist.
//
// The list began where the bar ends and stopped where the tab bar begins (trees/continuous/10.txt: {0, 91}, 670 high,
// clipped), so the rows scrolled up were cut off in a straight line under the glass buttons, a black band where the
// bar's blur used to be. Now the list is the page's whole height from its top edge, with the bar as its top inset and
// what the bars below take as its bottom inset, so rows run on under the glass the way Recents' do (Pages/Recents.x).
// Spotify's constraints put the frame back after each pass, so the view the list stands in is watched for its layout.
//
// A swipe back keeps the title's capsule on the bar until the page is gone (SGRUndressBarPage).
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kOwnFrameKey, kTopKey, kTakenKey, kWatchedKey;

// The page's list: the collection view as wide as the page.
static UICollectionView *listIn(UIView *view) {
    __block UICollectionView *list = nil;
    SGForEachView(view, ^(UIView *v) {
        if (!list && [v isKindOfClass:UICollectionView.class] && v.bounds.size.width >= view.bounds.size.width * 0.9) list = (UICollectionView *)v;
    });
    return list;
}

static void extendList(UIView *page, UICollectionView *list) {
    UIView *host = list.superview;
    if (!host || host.bounds.size.height < 1) return;
    CGFloat pageHeight = host.bounds.size.height;

    // What the bars take of the page is read off the list as Spotify's constraints leave it: whenever it is not in the
    // frame this pass put it in. Left alone while it is, so what was read stays.
    NSValue *own = objc_getAssociatedObject(list, &kOwnFrameKey);
    CGRect frame = list.frame;
    if (!own || !CGRectEqualToRect(own.CGRectValue, frame)) {
        objc_setAssociatedObject(list, &kTopKey, @(MAX(frame.origin.y, 0)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(list, &kTakenKey, @(MAX(pageHeight - CGRectGetMaxY(frame), 0)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat top = [objc_getAssociatedObject(list, &kTopKey) doubleValue];
    CGFloat taken = [objc_getAssociatedObject(list, &kTakenKey) doubleValue];

    CGRect wanted = CGRectMake(frame.origin.x, 0, frame.size.width, pageHeight);
    if (!CGRectEqualToRect(list.frame, wanted)) list.frame = wanted;
    objc_setAssociatedObject(list, &kOwnFrameKey, [NSValue valueWithCGRect:list.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (list.contentInsetAdjustmentBehavior != UIScrollViewContentInsetAdjustmentNever) list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    UIEdgeInsets inset = UIEdgeInsetsMake(top, 0, MAX(taken, page.safeAreaInsets.bottom), 0);
    UIEdgeInsets old = list.contentInset;
    BOOL moving = list.isDragging || list.isDecelerating;
    if (fabs(old.bottom - inset.bottom) < 0.5 && fabs(old.top - inset.top) < 0.5) {
        // A reload of the rows can send the list back to offset 0, which is the first row under the bar.
        if (!moving && inset.top > 0 && fabs(list.contentOffset.y) < 0.5) list.contentOffset = CGPointMake(0, -inset.top);
        return;
    }
    BOOL atTop = list.contentOffset.y <= -old.top + 1;
    list.contentInset = inset;
    list.verticalScrollIndicatorInsets = inset;
    if (atTop && !moving) list.contentOffset = CGPointMake(0, -inset.top);
}

static void dress(UIViewController *page) {
    SGRDressBarPage(page);
    UIView *view = page.viewIfLoaded;
    if (!view.window) return;
    UICollectionView *list = listIn(view);
    if (!list) return;
    extendList(view, list);
    UIView *host = list.superview;
    if (host && !objc_getAssociatedObject(host, &kWatchedKey)) {
        __weak UIViewController *weakPage = page;
        if (SGRObserveLayout(host, ^(UIView *laidOut) {
                UIViewController *strong = weakPage;
                UICollectionView *found = strong ? listIn(strong.viewIfLoaded) : nil;
                if (found) extendList(strong.viewIfLoaded, found);
            })) {
            objc_setAssociatedObject(host, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

%group SGRSongDNABlend
%hook SGRBlendController
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
    // The bar's buttons and title are made after the first layout.
    __weak UIViewController *weak = (UIViewController *)self;
    for (NSNumber *delay in @[@0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) dress(weak);
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    SGRUndressBarPage((UIViewController *)self);
}
%end
%end

%group SGRSongDNAArtists
%hook SGRArtistsController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SGRDressBarPage((UIViewController *)self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    SGRDressBarPage((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // The bar's buttons and title are made after the first layout.
    __weak UIViewController *weak = (UIViewController *)self;
    for (NSNumber *delay in @[@0.25, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) SGRDressBarPage(weak);
        });
    }
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
    Class page = SGRPageClass(@"SongDNA_ArtistsDNAPageImpl", @"BlendViewController");
    if (page) {
        // The page is hosted by a controller of Spotify's page template, which is the top of the stack.
        SGRRegisterBarPages(^BOOL(UIViewController *top) { return SGRPageIsOrHolds(top, page); });
        %init(SGRSongDNABlend, SGRBlendController = page);
    } else {
        SGLog(@"class SongDNA_ArtistsDNAPageImpl.BlendViewController not found, Song DNA keeps Spotify's bar");
    }
    Class artists = SGRPageClass(@"SongDNA_ArtistsDNAPageImpl", @"ArtistsDNAViewController");
    if (artists) {
        SGRRegisterBarPages(^BOOL(UIViewController *top) { return SGRPageIsOrHolds(top, artists); });
        %init(SGRSongDNAArtists, SGRArtistsController = artists);
    } else {
        SGLog(@"class SongDNA_ArtistsDNAPageImpl.ArtistsDNAViewController not found, the contributors' page keeps Spotify's bar");
    }
}
