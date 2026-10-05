// Playlist redesign: the navigation bar Spotify slides in as the page scrolls. It is a 103pt
// HeaderNavigationBar (trees/continuous 2026-10-05, 3.txt to 6.txt) holding a LegacyUI GradientView of the
// playlist's colour, which lies under the pinned Back and ⋯ buttons, and the playlist's name in an
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
// getter PlaylistHeader.x reads). Albums and artists have a HeaderNavigationBar too and are not touched:
// SGRPlaylistHeaderOf answers only for a playlist page.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRLegacyGlass.h"
#import "Playlist.h"
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

static void apply(UIView *bar) {
    UIViewController *headerVC = SGRPlaylistHeaderOf(bar);
    if (!headerVC || isLikedSongs(headerVC)) return;

    for (UIView *sub in bar.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"GradientView"]) hideScrim(sub);
    }
    if (SGIsVisibleColor(bar.layer.backgroundColor)) bar.backgroundColor = UIColor.clearColor;

    UILabel *text = nil;
    UIView *title = titleIn(bar, &text);
    if (!title || title.bounds.size.width < 1) return;
    CGFloat wanted = ceil([text sizeThatFits:CGSizeMake(CGFLOAT_MAX, kBubbleHeight)].width) + 2 * kBubblePadding;
    CGFloat width = MIN(MAX(wanted, kBubbleHeight), title.bounds.size.width);
    SGRGlassCapsuleInside(title, &kBubbleKey, CGSizeMake(width, kBubbleHeight), NO);
}

%hook _TtC28EncoreConsumerMobile_BaseKit19HeaderNavigationBar
- (void)layoutSubviews {
    %orig;
    apply((UIView *)self);
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
    if (!SGRedesignedUI() || !SGBelowIOS26()) return;
    %init;
    SGRequireClasses(@[@"_TtC28EncoreConsumerMobile_BaseKit19HeaderNavigationBar"]);
}
