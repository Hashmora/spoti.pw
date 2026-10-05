// The Redesign Kit: what every part of the redesign (Redesigned/<Part>/) builds on, so the screens share
// one look and nothing is hand-rolled per screen. A screen imports this and Core/PGCore.h.
//
//     PGRedesign.h   Redesigned UI, the one switch, and the flags the redesigned screens force
//     PGRTokens.h    colours, type, spacing, radii, motion, the accessibility settings
//     PGRPalette.h   the artwork's edge colour, the field colour and the pre-blurred bitmaps
//     PGRField.h     the artwork field behind a page
//     PGRFlow.h      the player's moving field of the artwork's colours
//     PGRGlass.h     glass inside Spotify's round controls
//     PGRGlyph.h     bare glyph overlays and glyph buttons
//     PGRActionRow.h the Play capsule and the stand-in button of a page's action row
//     PGRDownload.h  Spotify's download state, read, and the glyph drawn for it
//     PGRHeaderInfo.h a page header's title, creator, length, row and description, the Music app's
//     PGRRestyle.h   keeping Spotify's views restyled: suppress, digits, lookups, shadows, firing
//                    controls, taking a list cell's paint off the field
//     PGRBridges.h   player state, now playing artwork, the player's open and close
//     PGRRepaint.h   the areas the redesign keeps transparent when Spotify repaints them
//     PGRAccent.h    the redesign's accent colour; its AMOLED black is PGRAmoled.x, always on
//
// Every hook file of the redesign starts its %ctor with `if (!PGRedesignedUI()) return;` and every one
// of Native/ with `if (!PGNativeUI()) return;` (Core/PGUIMode.h), so the two looks never run together.
#import "PGRedesign.h"
#import "PGRTokens.h"
#import "PGRPalette.h"
#import "PGRField.h"
#import "PGRFlow.h"
#import "PGRGlass.h"
#import "PGRGlyph.h"
#import "PGRActionRow.h"
#import "PGRDownload.h"
#import "PGRHeaderInfo.h"
#import "PGRRestyle.h"
#import "PGRBridges.h"
#import "PGRRepaint.h"
#import "PGRAccent.h"
