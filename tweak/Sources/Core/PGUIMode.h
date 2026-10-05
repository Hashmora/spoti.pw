// The glass UI runs below iOS 26 only: from iOS 26 the system draws its own Liquid Glass and a second engine
// over it only conflicts (Redesigned/Navbar/TabBar.x). There is no switch: below iOS 26 it is on.
// Threading: safe from any thread.
#import <Foundation/Foundation.h>

BOOL PGRedesignAvailable(void);
BOOL PGRedesignedUI(void);
// Kept for the flag forcer's "locked" answer; the same as PGRedesignedUI() now that nothing is stored.
BOOL PGRedesignedUIStored(void);
