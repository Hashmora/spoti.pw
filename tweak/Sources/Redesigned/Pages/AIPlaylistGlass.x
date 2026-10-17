// Redesign: the cross of the AI playlist's chat on glass.
//
//   AI playlist   AIPlaylist_PlaylistCreationPageImpl.PlaylistCreationView (trees/continuous/6.txt): the header row's
//                 "Abort Playlist Creation" cross, and the "Close Chat" cross that takes its place once the chat has
//                 started, become glass circles, as the cross of Create cover art is (CoverArt/CoverArt.x).
//
// Both are Encore Tertiary buttons of the same frame, one shown at a time by Spotify, so each carries its own glass and
// the hidden one's goes with it. The button keeps its action and its accessibility: the glass is its own subview
// (Kit/SGRGlass.h). Nothing between the button and the page clips: the glass is 44pt inside a 48 x 52pt button, and
// the grown glass of a press (SGGlassInteractive) would be cut off at the button's edge if the button did, so the
// button and the plain views above it, up to the page, are let go of their clip.
#import "Core/SGCore.h"
#import "Core/SGGlassTouch.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Pages/Pages.h"

static char kCrossGlassKey;

static NSArray<NSString *> *crossIdentifiers(void) {
    return @[@"Components.UI.PlaylistCreationHeaderRow.DismissButton",
             @"Components.UI.PlaylistCreationHeaderRow.CloseChatButton"];
}

// The views from the button up to the page that are Spotify's plain containers: a scroll view's clip is its own to keep.
static void unclipPath(UIView *button, UIView *page) {
    for (UIView *view = button; view && view != page; view = view.superview) {
        if (view != button && ![view isMemberOfClass:UIView.class]) continue;
        if (view.clipsToBounds) view.clipsToBounds = NO;
    }
}

static void dressCross(UIView *page) {
    if (!page.window) return;
    NSArray<NSString *> *identifiers = crossIdentifiers();
    SGForEachView(page, ^(UIView *view) {
        if (![identifiers containsObject:view.accessibilityIdentifier ?: @""]) return;
        if (view.bounds.size.width < 1 || view.bounds.size.height < 1) return;
        UIView *glass = SGRGlassInside(view, &kCrossGlassKey, SGRGlassCircleSize);
        SGGlassInteractive(view, glass);
        unclipPath(view, page);
    });
}

%group SGRAIPlaylistGlass
%hook SGRPlaylistCreationView
- (void)layoutSubviews {
    %orig;
    dressCross((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    dressCross((UIView *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    Class page = SGRPageClass(@"AIPlaylist_PlaylistCreationPageImpl", @"PlaylistCreationView");
    if (page) {
        %init(SGRAIPlaylistGlass, SGRPlaylistCreationView = page);
    } else {
        SGLog(@"class AIPlaylist_PlaylistCreationPageImpl.PlaylistCreationView not found, the AI playlist's cross keeps Spotify's button");
    }
}
