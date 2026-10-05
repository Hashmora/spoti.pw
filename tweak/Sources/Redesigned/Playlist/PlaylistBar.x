// Playlist, album and artist redesign: the navigation bar Spotify slides in as the page scrolls. It is a
// 103pt HeaderNavigationBar (trees/continuous 2026-10-05, 3.txt to 6.txt) holding a LegacyUI GradientView of the
// page's colour, which lies under the pinned Back and ⋯ buttons, and the page's name in an
// SPTEncoreLabel centred between them. Under the redesign the page has no bar: the buttons float on their
// own glass, so the gradient goes and the name sits on a glass capsule of the same material as the buttons.
//
// PlaylistHeader.x's applyScrims conceals that gradient once, from the header's own pass, and in all four
// dumps it is not concealed (no `hidden masked`, unlike the page's other gradients), so Spotify had put
// it back or made it after the pass. This runs from the bar's own layout and window callbacks on every
// pass instead, which is when Spotify draws it.
//
// The capsule is a child of the name label (SGRGlassCapsuleInside), so it takes the label's alpha as
// Spotify fades the name in and out with the scroll, and it moves wherever the label does.
//
// Liked Songs keeps Spotify's bar as it is: the page's model says which it is (formatListType, the same
// getter PlaylistHeader.x reads). The album's bar is this one under the id
// CreativeWorkPlatform.HeaderNavigationBar (trees 2026-10-05, 6.txt:1350, 8.txt:1552, 103pt, its gradient only
// masked, never hidden) and the artist's sits in the header's HeaderForegroundView (7.txt:110, 100pt, its
// gradient not even masked), both with the name in the same SPTEncoreLabel 64pt tall. They are told apart
// from the page's other bars by the page having been dressed: the redesign pins its own Back on the page's
// root (SGRPinnedBack) for a playlist, an album and an artist, and for nothing else on the album's template,
// which a podcast's episode shares and leaves as Spotify's.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"
#import "Redesigned/Album/Album.h"
#import "Redesigned/Artist/Artist.h"
#import <objc/message.h>

static char kBubbleKey;

// Side padding of the name inside its capsule; the capsule is as tall as the buttons beside it.
static const CGFloat kBubblePadding = 18, kBubbleHeight = 44;

static BOOL isLikedSongs(UIViewController *headerVC) {
    SEL controllerSel = NSSelectorFromString(@"headerController"), modelSel = NSSelectorFromString(@"defaultHeaderViewModel"),
        typeSel = NSSelectorFromString(@"formatListType");
    if (![headerVC respondsToSelector:controllerSel]) return NO;
    id controller = ((id (*)(id, SEL))objc_msgSend)(headerVC, controllerSel);
    if (![controller respondsToSelector:modelSel]) return NO;
    id model = ((id (*)(id, SEL))objc_msgSend)(controller, modelSel);
    if (![model respondsToSelector:typeSel]) return NO;
    id type = ((id (*)(id, SEL))objc_msgSend)(model, typeSel);
    return [type isKindOfClass:NSString.class] && [type isEqualToString:@"liked-songs"];
}

// Invisible whatever Spotify does to it, as PlaylistHeader.x's conceal: the layer hidden, and an empty mask
// for when Spotify shows it anyway.
static void hideScrim(UIView *view) {
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
}

// The name: the one SPTEncoreLabel directly under the bar that holds text (the Back button's is a glyph
// in a button of its own, deeper down).
static UIView *titleIn(UIView *bar, UILabel **text) {
    for (UIView *sub in bar.subviews) {
        if (![NSStringFromClass(sub.class) hasSuffix:@"EncoreLabel"]) continue;
        for (UIView *inner in sub.subviews) {
            if ([inner isKindOfClass:UILabel.class] && ((UILabel *)inner).text.length) {
                if (text) *text = (UILabel *)inner;
                return sub;
            }
        }
    }
    return nil;
}

// An album's or an artist's bar, once the redesign has pinned its Back on the page: that button is a direct
// subview of the page's root, which only the pages dressed in AlbumHeader.x and ArtistHeader.x get.
static BOOL isDressedAlbumOrArtist(UIView *bar) {
    UIView *page = SGRAlbumPageOf(bar) ?: SGRArtistPageOf(bar);
    for (UIView *sub in page.subviews) {
        if ([sub isKindOfClass:SGRMirrorButton.class]) return YES;
    }
    return NO;
}

// Whether this bar is one the redesign dresses: a playlist's (Liked Songs apart), a dressed album's or artist's.
static BOOL handles(UIView *bar) {
    UIViewController *headerVC = SGRPlaylistHeaderOf(bar);
    return headerVC ? !isLikedSongs(headerVC) : isDressedAlbumOrArtist(bar);
}

static void apply(UIView *bar) {
    if (!handles(bar)) return;

    for (UIView *sub in bar.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"GradientView"]) hideScrim(sub);
    }
    if (SGIsVisibleColor(bar.layer.backgroundColor)) bar.backgroundColor = UIColor.clearColor;

    UILabel *text = nil;
    UIView *title = titleIn(bar, &text);
    if (!title || title.bounds.size.width < 1) return;
    // Spotify centres the name in the 64pt below the bar's top, 2pt under the pinned buttons' middle. The
    // label is moved by a transform, which Auto Layout never writes -- but the bar's layout may set the label's
    // frame, and a frame set under a transform moves the centre by the transform's opposite, so the move was
    // worked out from a centre it had itself displaced and grew with every pass until it was dropped as too
    // large, leaving the name where Spotify had it, 2pt low. The layout hook below puts the transform back to
    // identity before Spotify lays out, so what is read here is always the layout's own centre, and the move
    // is written only then: a pass of ours with a move on already (didMoveToWindow, a gradient added) leaves it.
    CGFloat middle = [title.superview convertPoint:title.center toView:nil].y;
    CGFloat shift = (bar.window.safeAreaInsets.top + SGRGlassCircleSize / 2) - middle;
    if (title.transform.ty == 0 && shift != 0 && fabs(shift) < 20) title.transform = CGAffineTransformMakeTranslation(0, shift);
    static NSInteger logged;
    static CGFloat lastShift = CGFLOAT_MAX;
    if (logged < 12 && fabs(shift - lastShift) > 0.01) {
        logged++;
        lastShift = shift;
        SGLog(@"redesign bar: name centre %.2f, buttons' middle %.2f, shift %.2f, transform %.2f, frame y %.2f", middle,
              bar.window.safeAreaInsets.top + SGRGlassCircleSize / 2, shift, title.transform.ty, title.frame.origin.y);
    }
    CGFloat wanted = ceil([text sizeThatFits:CGSizeMake(CGFLOAT_MAX, kBubbleHeight)].width) + 2 * kBubblePadding;
    CGFloat width = MIN(MAX(wanted, kBubbleHeight), title.bounds.size.width);
    SGRGlassCapsuleInside(title, &kBubbleKey, CGSizeMake(width, kBubbleHeight), NO);
}

%hook _TtC28EncoreConsumerMobile_BaseKit19HeaderNavigationBar
- (void)layoutSubviews {
    UIView *bar = (UIView *)self;
    if (handles(bar)) {
        UIView *title = titleIn(bar, NULL);
        if (title && title.transform.ty != 0) title.transform = CGAffineTransformIdentity;
    }
    %orig;
    apply(bar);
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) apply((UIView *)self);
}

// Spotify draws its colour back in from the scroll, with no layout pass of the bar's own.
- (void)didAddSubview:(UIView *)subview {
    %orig;
    if ([NSStringFromClass(subview.class) containsString:@"GradientView"]) apply((UIView *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC28EncoreConsumerMobile_BaseKit19HeaderNavigationBar"]);
}
