// Redesign: the cross of the AI playlist's chat on glass.
//
//   AI playlist   AIPlaylist_PlaylistCreationPageImpl.PlaylistCreationView (trees/continuous/6.txt): the header row's
//                 "Abort Playlist Creation" cross, and the "Close Chat" cross that takes its place once the chat has
//                 started, become glass circles, as the cross of Create cover art is (CoverArt/CoverArt.x).
//
//   Onboarding    the first screen, "Your playlist playground awaits" (trees/continuous/6.txt:243-258): a plain container the size of
//                 the screen that is the page's sibling, over it, holds the story and its own cross, "Components.UI.OnboardingView.CloseButton",
//                 a Tertiary button 48 x 48 at the corner. It is not inside the page, so the page's passes never met it and it
//                 showed as Spotify's bare cross, 4pt left of and 6pt above the header row's (that button is 48 x 52 at (4, 4) in its row).
//                 It gets the same glass circle, and is moved by that much so the cross does not jump when the chat begins.
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

#pragma mark - the first screen's cross

static NSString *const kOnboardingCross = @"Components.UI.OnboardingView.CloseButton";
// Where the header row's cross is from this one: its button sits at (4, 4) in the row, this one at the row's own corner, and
// 52pt high against 48 puts the centre of its glyph 2pt lower still.
static const CGFloat kOnboardingShiftX = 4, kOnboardingShiftY = 6;

// A cross dressed from its own button's passes, not only from the page's: the page is not laid out again while the first screen
// stands over it (6.txt:42-47 holds the header row's buttons with no glass in them), and a button laid out at no size on the
// page's first pass is met again only by its own.
static void dressCrossButton(UIView *button) {
    NSString *identifier = button.accessibilityIdentifier;
    if (!identifier.length) return;
    BOOL onboarding = [identifier isEqualToString:kOnboardingCross];
    if (!onboarding && ![crossIdentifiers() containsObject:identifier]) return;
    if (!button.window || button.bounds.size.width < 1 || button.bounds.size.height < 1) return;
    UIView *glass = SGRGlassInside(button, &kCrossGlassKey, SGRGlassCircleSize);
    SGGlassInteractive(button, glass);
    if (button.clipsToBounds) button.clipsToBounds = NO;
    if (!onboarding) return;
    CGAffineTransform shift = CGAffineTransformMakeTranslation(kOnboardingShiftX, kOnboardingShiftY);
    if (!CGAffineTransformEqualToTransform(button.transform, shift)) button.transform = shift;
}

%group SGRAIPlaylistButtons
%hook SGRTertiaryButton
- (void)layoutSubviews {
    %orig;
    dressCrossButton((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    dressCrossButton((UIView *)self);
}
%end
%end

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
    // Encore's Tertiary button, by the name the trees print: the three crosses are, the first screen's outside the page's view.
    Class tertiary = NSClassFromString(@"_TtCCE16Encore_ButtonKitO16EncoreFoundation6Encore6Button8Tertiary");
    if (tertiary) {
        %init(SGRAIPlaylistButtons, SGRTertiaryButton = tertiary);
    } else {
        SGLog(@"class Encore Button Tertiary not found, the AI playlist's first screen keeps Spotify's cross");
    }
}
