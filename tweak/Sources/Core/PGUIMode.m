#import "PGUIMode.h"
#import "PGLog.h"

BOOL PGRedesignAvailable(void) {
    if (@available(iOS 26.0, *)) return NO;
    return YES;
}

BOOL PGRedesignedUI(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        on = PGRedesignAvailable();
        PGLog(@"ui: glass %@", on ? @"on" : @"off (iOS 26 has its own)");
    });
    return on;
}

BOOL PGRedesignedUIStored(void) {
    return PGRedesignedUI();
}
