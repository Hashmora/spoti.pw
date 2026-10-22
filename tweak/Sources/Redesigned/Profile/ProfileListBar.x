// Profile lists, iOS < 26: Followers, Following and the playlists of a person. The page is a table under
// SPNavigationBar, UIKit's bar, which Spotify backs with a dark blur of its own. Here the bar is dressed as the
// playlist's is: the blur gone, Back a glass circle pinned to the corner, the title on a glass capsule. That is the
// bar of Pages/PageBar.m, the one Recents and Your Updates have.
//
// Tree (trees/continuous/7.txt, 8.txt, 9.txt): the page is a plain view holding Profile_CommonImpl.ProfileListView,
// whose UITableView is the size of the screen on #000000, so the list already runs under the bar. In the
// navigation controller's view, over the page, a plain UIView 390x91 holding a UIVisualEffectView (#1C1C1C@0.73),
// then SPNavigationBar with Back (_UIButtonBarButton), the title in a _UINavigationBarTitleControl and an empty
// trailing stack: no page of these has a ⋯.
//
// The earlier version hooked a Swift view controller by its mangled name and dressed the bar only while that
// class was on top; the trees above show the bar untouched, so that class was never met. The page is now
// recognised by what it holds, ProfileListView in the top page's view, which the trees show, so no controller
// name is needed. The dressing is done from the bar's own passes (UIKit builds the bar's buttons and its title
// control again whenever the item changes, after the bar's pass, so the content view's pass is watched too) and
// given back as another page comes on top.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Pages/Pages.h"
#import "Profile.h"

// The profile list dressed now; the bar is given back when it is no longer on top.
static __weak UIViewController *sg_dressedList;

// Whether `view` is, or holds within a few levels, the profile list's view.
static BOOL holdsProfileList(UIView *view, int depth) {
    if ([NSStringFromClass(view.class) hasSuffix:@"Profile_CommonImpl.ProfileListView"]
        || [NSStringFromClass(view.class) hasSuffix:@"Profile_CommonImpl15ProfileListView"]) return YES;
    if (depth <= 0) return NO;
    for (UIView *sub in view.subviews) {
        if (holdsProfileList(sub, depth - 1)) return YES;
    }
    return NO;
}

static void update(UIView *bar) {
    if (!SGBelowiOS26()) return;
    UINavigationController *navigation = SGRNavigationOf(bar);
    UIViewController *top = navigation.topViewController;
    UIView *view = top.viewIfLoaded;
    if (top && view.window && holdsProfileList(view, 4)) {
        if (sg_dressedList != top) {
            sg_dressedList = top;
            SGLog(@"redesign profile: bar dressed for %@", NSStringFromClass(top.class));
        }
        SGRDressBarPage(top);
        return;
    }
    UIViewController *dressed = sg_dressedList;
    if (dressed) {
        sg_dressedList = nil;
        SGRUndressBarPage(dressed);
    }
}

%hook SPNavigationBar
- (void)layoutSubviews {
    %orig;
    update((UIView *)self);
}
%end

// UIKit rebuilds the bar's buttons and title while laying this view out, which is after the bar's own pass.
%hook _UINavigationBarContentView
- (void)layoutSubviews {
    %orig;
    UIView *bar = ((UIView *)self).superview;
    if ([bar isKindOfClass:NSClassFromString(@"SPNavigationBar")]) update(bar);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"SPNavigationBar", @"_UINavigationBarContentView"]);
    // Spotify's bar is kept out of sight from the push, not from the first pass that finds the list.
    SGRRegisterBarPages(^BOOL(UIViewController *top) {
        UIView *view = top.viewIfLoaded;
        return view && holdsProfileList(view, 4);
    });
}
