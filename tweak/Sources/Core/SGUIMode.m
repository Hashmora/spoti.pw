#import "SGUIMode.h"
#import "SGLog.h"
#import "SGPrefs.h"

BOOL SGRedesignAvailable(void) {
    // Редизайн — это подмена системного Liquid Glass для тех, у кого его ещё нет.
    // На iOS 26+ система уже рисует свой UIGlassEffect, и второй, кастомный, движок
    // поверх него не нужен и конфликтует (см. TabBar.x). Поэтому редизайн целиком,
    // включая навбар и обработку кнопок, доступен только ниже iOS 26.
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
