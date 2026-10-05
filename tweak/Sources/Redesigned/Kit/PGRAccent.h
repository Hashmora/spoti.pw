// The redesign's accent colour in place of Spotify's green (PGRAccent.x), chosen apart from the native
// look's and stored under its own key; unset is #37F200, negative keeps Spotify's own green.
#import <UIKit/UIKit.h>

#define PGRKeyAccent @"pureglass.redesign.accent"   // 0xRRGGBB

UIColor *PGRAccentColor(void);   // nil while Spotify's own green is kept
NSString *PGRAccentLabel(void);  // "#RRGGBB", or the name of Spotify's own
