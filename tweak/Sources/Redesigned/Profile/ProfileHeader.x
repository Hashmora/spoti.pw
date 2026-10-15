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
//
// The row of Follow / Message / Share under the name used to sit still under the pill as the page scrolled, though
// nothing in the bar needs it any more (trees/continuous/13.txt): it fades out over the first kActionsFade points of
// scroll, followed from the list's own -setContentOffset:.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Pages/Pages.h"
#import "Profile.h"

static char kHeaderKey, kMoreKey, kBarMoreKey, kPinnedMoreKey, kShareKey, kFollowKey;

// Points of scroll over which the action row goes from fully shown to gone.
static const CGFloat kActionsFade = 60;
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

// The row holding Follow / Message / Share: the widest ancestor of the Share button that is still no taller than a
// button's row, below the header's content stack (13.txt: 44pt rows under a 241pt stack).
static UIView *actionsRowOf(UIView *header) {
    UIView *row = SGRFindByIdentifier(header, @"Components.UI.ShareButton", &kShareKey);
    for (int i = 0; row && i < 6; i++) {
        UIView *up = row.superview;
        if (!up || up == header || up.bounds.size.height > 60) break;
        row = up;
    }
    return row;
}

static UIScrollView *profileList(UIView *page) {
    for (UIView *sub in page.subviews) {
        if ([sub isKindOfClass:UICollectionView.class] && sub.bounds.size.height > 300) return (UIScrollView *)sub;
    }
    return nil;
}

static void fadeActions(UIView *page, UIScrollView *list) {
    UIView *header = SGRFindByIdentifier(page, @"Components.UI.ProfileHeader", &kHeaderKey);
    UIView *row = header ? actionsRowOf(header) : nil;
    if (!row) return;
    CGFloat scrolled = MAX(0, list.contentOffset.y + list.adjustedContentInset.top);
    CGFloat alpha = 1 - MIN(1, scrolled / kActionsFade);
    if (fabs(row.alpha - alpha) > 0.005) row.alpha = alpha;
    BOOL touchable = alpha > 0.3;
    if (row.userInteractionEnabled != touchable) row.userInteractionEnabled = touchable;
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

    UIScrollView *list = profileList(page);
    if (list) {
        if (!objc_getAssociatedObject(list, &kFollowKey)) {
            __weak UIView *weakPage = page;
            void (^follow)(UIScrollView *) = ^(UIScrollView *scroll) {
                UIView *strong = weakPage;
                if (strong) fadeActions(strong, scroll);
            };
            objc_setAssociatedObject(list, &kFollowKey, follow, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        fadeActions(page, list);
    }

    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign profile: header dressed, ⋯ %@", more ? NSStringFromClass(more.class) : @"not found");
    }
}

%group SGRProfileScroll
%hook UIScrollView
- (void)setContentOffset:(CGPoint)offset {
    %orig;
    void (^follow)(UIScrollView *) = objc_getAssociatedObject(self, &kFollowKey);
    if (follow) follow(self);
}
%end
%end

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
        %init(SGRProfileScroll);
    } else {
        SGLog(@"class Profile_CommonImpl.ProfileView not found, the profile page keeps Spotify's header");
    }
}
