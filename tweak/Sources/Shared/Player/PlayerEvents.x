// The player's open and close, told from the appearance callbacks of a controller inside the player,
// which UIKit sends as the presentation or the dismissal begins, whatever animates it; the transition
// coordinator says when it is over, a cancelled swipe included. Spotify 9.1.78 presents the player
// through SPTBarInteractivePresentationController, never through NowPlaying_ViewPageImpl's
// Show/CloseFullscreenAnimatedTransitioning animators, whose hooks never once fired.
#import "Core/PGCore.h"
#import "PlayerEvents.h"

NSString *const PGPlayerTransitionNotification = @"pureglass.playerTransition";
NSString *const PGPlayerTransitionEndedNotification = @"pureglass.playerTransitionEnded";
static CFTimeInterval pg_transitionEnds;
static NSUInteger pg_transitionGeneration;

CFTimeInterval PGPlayerTransitionEnds(void) {
    return pg_transitionEnds > CACurrentMediaTime() ? pg_transitionEnds : 0;
}

static void announceTransition(UIViewController *unit, BOOL animated, NSString *what) {
    id<UIViewControllerTransitionCoordinator> coordinator = unit.transitionCoordinator;
    if (!animated || !coordinator) return;
    NSTimeInterval duration = MAX(0.1, coordinator.transitionDuration);
    NSUInteger generation = ++pg_transitionGeneration;
    pg_transitionEnds = CACurrentMediaTime() + duration;
    [NSNotificationCenter.defaultCenter postNotificationName:PGPlayerTransitionNotification object:nil];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (generation != pg_transitionGeneration) return;
        pg_transitionEnds = 0;
        [NSNotificationCenter.defaultCenter postNotificationName:PGPlayerTransitionEndedNotification object:nil];
    }];
    static dispatch_once_t once;
    dispatch_once(&once, ^{ PGLog(@"player %@ over %.2fs, by its appearance callbacks", what, duration); });
}

%hook _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    announceTransition((UIViewController *)self, animated, @"opens");
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    announceTransition((UIViewController *)self, animated, @"closes");
}
%end

%ctor {
    %init;
    PGRequireClasses(@[@"_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController"]);
}
