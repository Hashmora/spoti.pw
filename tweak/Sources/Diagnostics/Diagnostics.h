// Screen dumps for FLEX builds: the visible screen's view tree, served over the phone's loopback
// and logged when the app goes to the background.
#import <Foundation/Foundation.h>

BOOL PGIsDebugBuild(void);
NSString *PGScreenTree(void);
void PGDumpScreen(NSString *reason);
