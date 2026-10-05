// Home hooks time their work through these; the scroll meter that read the numbers is not part of this tweak.
#import "Home.h"

CFTimeInterval PGRHomeProbeBegin(void) { return 0; }
void PGRHomeProbeEnd(PGRHomeProbe probe, CFTimeInterval began) {}
