// Profile redesign, iOS < 26: the header of a person's own page (Profile_CommonImpl.ProfileView). It has the header the
// playlist, album and artist pages have (HeaderNavigationBar, Spotify's bar that slides in as the page scrolls), so it
// gets what they get: Back and ⋯ as glass circles pinned to the corners of the page, level with each other, and the
// name in the bar on a glass capsule (Playlist/PlaylistBar.x, which takes a dressed profile as it takes an album).
//
// Tree (trees/continuous/2.txt): ProfileView holds the list and, over it, a LegacyUI_ECMCoreKit.HeaderLayout
// (id=Components.UI.ProfileHeader) with the HeaderNavigationBar (a GradientView, the name, Components.Header.UI.BackButton
// and a stack with Components.UI.NavigationBarContextMenuButton) and, in the content beside the name, a ⋯ of the
// header's own (Components.UI.ContextMenuButton).
//
// Nothing here is a control of the redesign's own making: the pinned ⋯ fires Spotify's ⋯ (SGRPinnedMore), so the menu is
// Spotify's own sheet, which the redesign dresses; below iOS 26 no page's ⋯ opens the system menu (ContextMenu/ContextMenu.x).
// Both of Spotify's ⋯ are concealed under the pinned one, not removed.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Pages/Pages.h"
#import "Profile.h"

static char kHeaderKey, kMoreKey, kBarMoreKey, kPinnedMoreKey;
static Class sg_profileView;

UIView *SGRProfilePageOf(UIView *view) {
    if (!sg_profileView) return nil;
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:sg_profileView]) return v;
    }
    return nil;
}

// Invisible whatever Spotify does to it: the layer hidden, and an empty mask for when Spotify shows it anyway. The
// control is still there to be fired.
static void conceal(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static void dress(UIView *page) {
    if (!page.window || page.bounds.size.width < 1) return;
    UIView *header = SGRFindByIdentifier(page, @"Components.UI.ProfileHeader", &kHeaderKey);
    if (!header) return;
    UIView *barMore = SGRFindByIdentifier(header, @"Components.UI.NavigationBarContextMenuButton", &kBarMoreKey);
    UIView *contentMore = SGRFindByIdentifier(header, @"Components.UI.ContextMenuButton*", &kMoreKey);
    UIView *more = contentMore ?: barMore;
    SGRPinnedMore(page, &kPinnedMoreKey, more);
    SGRPinnedBack(page, header);
    conceal(barMore);
    conceal(contentMore);

    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign profile: header dressed, ⋯ %@", more ? NSStringFromClass(more.class) : @"not found");
    }
}

%group SGRProfileHeader
%hook SGRProfileView
- (void)layoutSubviews {
    %orig;
    dress((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) dress((UIView *)self);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class page = SGRPageClass(@"Profile_CommonImpl", @"ProfileView");
    if (page) {
        sg_profileView = page;
        %init(SGRProfileHeader, SGRProfileView = page);
    } else {
        SGLog(@"class Profile_CommonImpl.ProfileView not found, the profile page keeps Spotify's header");
    }
}
