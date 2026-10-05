// The glass UI runs below iOS 26 only: from iOS 26 the system draws its own Liquid Glass and a second engine
// over it only conflicts (Redesigned/Navbar/TabBar.x). Below it the glass is off until Legacy Glass is
// switched on, a row this tweak puts into spoti.pw's Mod Settings > Appearance, under Redesigned UI
// (Shared/Settings/LegacyGlassRow.x). It is read once, so a change waits for the restart. With it on, this
// tweak is the one that draws the tab bar, whatever spoti.pw's own redesign does.
// Threading: safe from any thread.
#import <Foundation/Foundation.h>

#define PGKeyLegacyGlass @"pureglass.legacyGlass"

BOOL PGRedesignAvailable(void);
BOOL PGRedesignedUI(void);
// The stored switch rather than the launch's, for the flag forcer's "locked" answer.
BOOL PGRedesignedUIStored(void);
