// Made For You (SPTMadeForYouHubViewController, a Hub page): the redesign's bar over the list (Pages/PageBar.m),
// Spotify's header gone, the title "Made For You" on a glass capsule and Back a glass circle, and the covers of its
// cards cut at the radius Home's are.
//
// Tree (trees/continuous/27.txt): HUBContainerView holds a HUBCollectionView the size of the screen on #000000 with
// the rows of cards (a HUGSCarouselComponentView each, :22), and over it the navigation controller's blur
// (390x91, #1C1C1C@0.73, :280) and SPNavigationBar with Back and the title control, a UILabel "Made For You" (:303-305).
// The list already runs under the bar, so only the bar changes.
//
// A card is a GLUEEntityCardView 162x224 (:29): a plain view 162x162 that clips and holds the cover, a GLUEImageView
// that clips too (:30-31), and the text under it. Both have no radius of their own, so the cover is square; Home's
// covers are cut at SGRRadiusCover, continuous (Home/HomeCards.x), and these are now. Only the cards of this page are:
// the card's view controller says which page it is on.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

// Below this a card's picture is a glyph or a placeholder, not a cover (Home/HomeCards.x).
static const CGFloat kCoverMinWidth = 80;

static Class sg_madeForYou;

static void roundCorners(UIView *view, CGFloat radius) {
    CALayer *layer = view.layer;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
    if (!layer.masksToBounds) layer.masksToBounds = YES;
}

// Whether the card is on the Made For You page: the first view controller up its responder chain.
static BOOL onPage(UIView *card) {
    for (UIResponder *r = card.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) return [r isKindOfClass:sg_madeForYou];
    }
    return NO;
}

static void roundCover(UIView *card) {
    if (!onPage(card)) return;
    for (UIView *holder in card.subviews) {
        // The text under the cover is the card's details view; the cover's holder is the plain view above it.
        if (![holder isMemberOfClass:UIView.class] || holder.bounds.size.width < kCoverMinWidth) continue;
        roundCorners(holder, SGRRadiusCover);
        for (UIView *image in holder.subviews) {
            if (image.bounds.size.width >= kCoverMinWidth) roundCorners(image, SGRRadiusCover);
        }
    }
}

%group SGRMadeForYouBar
%hook SGRMadeForYouPage
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
    SGRRepeatPass((UIViewController *)self, @[@0.25, @0.6], ^(UIViewController *c) { SGRDressBarPage(c); });
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    SGRUndressBarPage((UIViewController *)self);
}
%end
%end

%group SGRMadeForYouCards
%hook SGRGlueCard
- (void)layoutSubviews {
    %orig;
    roundCover((UIView *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class page = NSClassFromString(@"SPTMadeForYouHubViewController");
    if (!page) {
        SGLog(@"class SPTMadeForYouHubViewController not found, Made For You keeps Spotify's bar and covers");
        return;
    }
    sg_madeForYou = page;
    SGRRegisterBarPages(^BOOL(UIViewController *top) { return SGRPageIsOrHolds(top, page); });
    %init(SGRMadeForYouBar, SGRMadeForYouPage = page);
    Class card = NSClassFromString(@"GLUEEntityCardView");
    if (card) {
        %init(SGRMadeForYouCards, SGRGlueCard = card);
    } else {
        SGLog(@"class GLUEEntityCardView not found, the covers on Made For You stay square");
    }
}
