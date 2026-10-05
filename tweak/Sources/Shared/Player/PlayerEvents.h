// The full screen player's open and close, for whatever must stand still while it animates (the
// karaoke card puts its display link down, the redesign holds heavy work back). Both looks' players are
// presented by Spotify's own presentation controller, so one announcement serves both.
#import <UIKit/UIKit.h>

// Posted as the player starts to open or close, before the animation runs, and again once it is
// over; PGPlayerTransitionEnds says when it is expected to be over (as CACurrentMediaTime), 0 when none runs.
extern NSString *const PGPlayerTransitionNotification;
extern NSString *const PGPlayerTransitionEndedNotification;
CFTimeInterval PGPlayerTransitionEnds(void);
