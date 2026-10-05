// What the harness does not compile: the accent hook (PGRAccent.x), the repaint hook (PGRRepaint.x), the
// tab bar's composition (Navbar.x) and Mod Settings. Spotify's order of tabs stays as the mock has it.
#import <UIKit/UIKit.h>

UIColor *PGRAccentColor(void) { return nil; }
__weak UIView *pgr_nowPlayingRoot = nil;
__weak UIView *pgr_nowPlayingCard = nil;
__weak UIView *pgr_lyricsPageRoot = nil;
__weak UIView *pgr_playlistRoot = nil;
__weak UIView *pgr_albumRoot = nil;
__weak UIView *pgr_artistRoot = nil;

void PGRComposeTabBar(UIView *tabBar) {}
void PGOpenModSettings(UIView *source) {}
