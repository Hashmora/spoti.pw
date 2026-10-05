#import "PGUIMode.h"
#import "PGLog.h"
#import "PGPrefs.h"

BOOL PGRedesignAvailable(void) {
    if (@available(iOS 26.0, *)) return NO;
    return YES;
}

BOOL PGRedesignedUI(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        on = PGRedesignedUIStored();
        PGLog(@"ui: glass %@", on ? @"on" : (PGRedesignAvailable() ? @"off (Glass UI is off)" : @"off (iOS 26 has its own)"));
    });
    return on;
}

BOOL PGRedesignedUIStored(void) {
    return PGRedesignAvailable() && PGFlag(PGKeyLegacyGlass, NO);
}
