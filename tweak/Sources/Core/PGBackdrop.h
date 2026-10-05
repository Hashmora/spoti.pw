// The cover art as a background: shrunk until no shape of it survives, blurred, under a scrim
// darkening towards the bottom. Native/Player/Player.x puts one behind the player, Native/Playlist/Playlist.x
// behind the playlist header.
#import <UIKit/UIKit.h>

UIImage *PGBackdropSample(UIImage *cover);
// The scrim runs from 0.40 black at the top to `bottomAlpha` at the bottom.
UIView *PGBackdropMake(CGRect frame, CGFloat bottomAlpha);
UIImageView *PGBackdropImageView(UIView *backdrop);
