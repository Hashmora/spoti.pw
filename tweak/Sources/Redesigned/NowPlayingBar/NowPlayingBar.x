// The redesign's now playing bar: the album-coloured card becomes a glass card with round artwork and the
// progress line under the text. Spotify's own labels, buttons and gestures stay in place.
//
// The full screen player morphs the bar's own card and artwork into the cover art. The bar was
// written to hand itself back to Spotify for that animation, from NowPlaying_ViewPageImpl's
// Show/CloseFullscreenAnimatedTransitioning, but Spotify 9.1.78 never runs the player through those,
// so the handback never happened and is gone; if the morph ever reads as a cut, the place to start is
// Shared/Player/PlayerEvents.h, which does fire. What does move with the player is a stand-in of the
// bar, which BarTransition.x keeps glass behind.
//
// Tree (trees/home.txt): NowPlayingBarContainerViewController.view 402x56 > NowPlayingBarViewController.view
//   at {8,0} 386x56 > UIView 386x56 (the painted card) > artwork 40x40 r=4, title stack,
//   progress line 370x2 at the bottom. The glass pane goes on the container's view.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "NowPlayingBar.h"
#import "Redesigned/Navbar/Navbar.h"

static const CGFloat kCardRadius = 24;
static char kGlassKey;
static char kTintKey;
static __weak UIView *sg_cardGlass;
static __weak UIView *sg_cardArtwork;
static __weak UIView *sg_container;

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius) {
    UIView *glass = sg_cardGlass;
    if (!glass.superview || !glass.window || !host) return CGRectNull;
    if (radius) *radius = MIN(kCardRadius, glass.bounds.size.height / 2);
    return [host convertRect:glass.bounds fromView:glass];
}

CGRect SGRNowPlayingArtworkFrameIn(UIView *host) {
    UIView *artwork = sg_cardArtwork;
    if (!artwork.window || !host) return CGRectNull;
    return [host convertRect:artwork.bounds fromView:artwork];
}

#pragma mark - for the compact row

UIView *SGRNowPlayingContainerView(void) {
    UIView *container = sg_container;
    return container.window ? container : nil;
}

// Spotify's own labels, top to bottom: the title, then the artist. A third line (the device the music is
// on) is left out by taking two.
static NSArray<UILabel *> *textLabels(UIView *bar) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(bar, ^(UIView *v) {
        UILabel *label = [v isKindOfClass:UILabel.class] ? (UILabel *)v : nil;
        if (label && !label.hidden && label.alpha > 0.01 && label.text.length && label.bounds.size.width > 0) [labels addObject:label];
    });
    return [labels sortedArrayUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        return [@(SGFrameIn(a, bar).origin.y) compare:@(SGFrameIn(b, bar).origin.y)];
    }];
}

// The play/pause button: the one the accessibility label names, else the right-most control of the bar's
// size (Spotify lays the card out connect, heart, play).
static UIView *playControl(UIView *bar) {
    __block UIView *named = nil, *rightmost = nil;
    __block CGFloat bestX = -CGFLOAT_MAX;
    SGForEachView(bar, ^(UIView *v) {
        CGFloat width = v.bounds.size.width;
        if (v.hidden || v.alpha < 0.01 || width < 20 || width > 100) return;
        NSString *label = v.accessibilityLabel.lowercaseString;
        if (!named && ([label hasPrefix:@"play"] || [label hasPrefix:@"pause"])) named = v;
        if ([v isKindOfClass:UIControl.class]) {
            CGFloat x = SGFrameIn(v, bar).origin.x;
            if (x > bestX) { bestX = x; rightmost = v; }
        }
    });
    return named ?: rightmost;
}

BOOL SGRNowPlayingState(NSString **title, NSString **artist, UIImage **artwork, BOOL *playing) {
    UIView *bar = sgr_nowPlayingRoot;
    if (!bar.window) return NO;
    NSArray<UILabel *> *labels = textLabels(bar);
    if (!labels.count) return NO;
    if (title) *title = labels[0].text;
    if (artist) *artist = labels.count > 1 ? labels[1].text : nil;
    if (artwork) {
        __block UIImage *image = nil;
        SGForEachView(sg_cardArtwork ?: bar, ^(UIView *v) {
            if (!image && [v isKindOfClass:UIImageView.class]) image = ((UIImageView *)v).image;
        });
        *artwork = image;
    }
    if (playing) {
        // The button reads "Pause" while the music plays and "Play" while it does not.
        NSString *label = playControl(bar).accessibilityLabel.lowercaseString;
        *playing = [label hasPrefix:@"pause"];
    }
    return YES;
}

void SGRNowPlayingTogglePlay(void) {
    UIView *control = playControl(sgr_nowPlayingRoot);
    if (control) SGRForwardTap(control);
}

// The card, then the views above it up to the container: a tap recognizer for the whole bar sits on one of
// those, and going down instead would find the play button's first.
void SGRNowPlayingOpen(void) {
    UIView *container = sg_container;
    for (UIView *v = sgr_nowPlayingCard ?: sgr_nowPlayingRoot; v; v = v.superview) {
        if (SGRFireTapRecognizers(v)) return;
        if (v == container) return;
    }
}

static UIView *detectColoredCard(UIView *bar) {
    __block UIView *best = nil;
    __block CGFloat bestArea = 0;
    SGForEachView(bar, ^(UIView *v) {
        if ([v isKindOfClass:UIVisualEffectView.class] || SGKeepsColor(v) || !SGLooksLikeCard(v, v.layer.backgroundColor)) return;
        CGFloat area = v.bounds.size.width * v.bounds.size.height;
        if (area > bestArea) { bestArea = area; best = v; }
    });
    return best;
}

// Fallback when nothing is painted: the box around artwork, text and the small buttons.
static CGRect contentBounds(UIView *bar, UIView *target) {
    __block CGRect box = CGRectNull;
    SGForEachView(bar, ^(UIView *v) {
        if (v.hidden || v.alpha == 0) return;
        CGFloat width = v.bounds.size.width;
        BOOL content = ([v isKindOfClass:UIImageView.class] && width >= 20 && width <= 120)
            || [v isKindOfClass:UILabel.class]
            || ([v isKindOfClass:UIControl.class] && width <= 100);
        if (content) box = CGRectUnion(box, SGFrameIn(v, target));
    });
    return CGRectIsNull(box) ? box : CGRectInset(box, -10, -8);
}

static void roundView(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
}

static void restyleCardContent(UIView *card) {
    SGForEachView(card, ^(UIView *v) {
        CGSize size = v.bounds.size;
        BOOL square = size.width >= 36 && size.width <= 48 && fabs(size.width - size.height) < 1;
        if (!square || v.layer.cornerRadius <= 0) return;
        if (v.layer.cornerRadius >= size.width / 2) {
            if (!sg_cardArtwork) sg_cardArtwork = v;
            return;
        }
        UIView *outer = v;
        for (UIView *u = v; u && u != card && CGSizeEqualToSize(u.bounds.size, size); u = u.superview) {
            roundView(u, size.width / 2);
            u.clipsToBounds = YES;
            outer = u;
        }
        sg_cardArtwork = outer;
    });
    SGForEachView(card, ^(UIView *v) {
        CGRect f = v.frame;
        if (f.size.height > 3 || f.size.width < 200 || v.superview.bounds.size.height < 40) return;
        CGRect target = CGRectMake(52, card.bounds.size.height - 6, 226, 2);
        if (CGRectEqualToRect(f, target)) return;
        v.frame = target;
        [v setNeedsLayout];
        [v layoutIfNeeded];
    });
}

static void styleNowPlayingBar(UIViewController *container) {
    UIViewController *barVC = container.childViewControllers.firstObject;
    UIView *bar = barVC.viewIfLoaded ?: container.view;
    sgr_nowPlayingRoot = bar;
    sg_container = container.view;

    UIView *card = sgr_nowPlayingCard;
    if (!card || !SGIsInside(card, bar)) card = sgr_nowPlayingCard = detectColoredCard(bar);

    container.view.layer.backgroundColor = NULL;
    SGStripBackgrounds(bar);

    CGRect frame = card ? SGFrameIn(card, container.view) : contentBounds(bar, container.view);
    if (CGRectIsNull(frame)) return;
    frame.size.height = MIN(frame.size.height, 80);
    if (frame.size.height < 30 || frame.size.width < 100) return;

    CGFloat radius = MIN(kCardRadius, frame.size.height / 2);
    if (card) {
        roundView(card, radius);
        restyleCardContent(card);
    }

    UIView *glass = SGGlassFor(container.view, &kGlassKey);
    // Dark whatever the system is set to: the bar is outside the navigation stacks Spotify makes dark, and
    // took the system's light glass on a phone in light mode (TabBar.x).
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    sg_cardGlass = glass;
    glass.frame = frame;
    SGShapeGlass(glass, radius, NO);

    SGRGlassFilm(container.view, &kTintKey, glass, radius);

    SGRCompactBarNowPlayingChanged();

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"now playing card %@ at %@ (bar %@, container %@)", card.class, NSStringFromCGRect(frame),
              NSStringFromCGRect(bar.frame), NSStringFromCGRect(container.view.bounds));
    });
}

%hook _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    styleNowPlayingBar((UIViewController *)self);
}
%end

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *parent = ((UIViewController *)self).parentViewController;
    if ([NSStringFromClass(parent.class) containsString:@"NowPlayingBarContainer"]) styleNowPlayingBar(parent);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController",
        @"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController",
    ]);
}
