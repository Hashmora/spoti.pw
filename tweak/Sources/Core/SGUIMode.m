#import "SGUIMode.h"
#import "SGLog.h"
#import "SGPrefs.h"

BOOL SGRedesignAvailable(void) {
    // The redesign stands in for the system's Liquid Glass where there is none. From iOS 26 the system
    // draws its own, and a second engine over it only conflicts (Redesigned/Navbar/TabBar.x).
    if (@available(iOS 26.0, *)) return NO;
    return YES;
}

BOOL SGRedesignedUI(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        on = SGRedesignedUIStored();
        SGLog(@"ui: %@%@", on ? @"redesigned" : @"native", SGRedesignAvailable() ? @"" : @" (the redesign needs iOS 26)");
    });
    return on;
}

BOOL SGNativeUI(void) {
    return !SGRedesignedUI();
}

BOOL SGRedesignedUIStored(void) {
    // The stored switch is left alone rather than turned off: a phone updated to iOS 26 gets the
    // redesign it was last asked for back.
    return SGRedesignAvailable() && SGFlag(SGKeyRedesign, NO);
}
