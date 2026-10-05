#import "PGPrefs.h"

BOOL PGFlag(NSString *key, BOOL fallback) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    id value = [store objectForKey:key];
    if (value) return [value boolValue];
    return fallback && ![store boolForKey:PGKeyStock];
}

BOOL PGEnabled(NSString *key) {
    return PGFlag(key, YES);
}

BOOL PGHidden(NSString *key) {
    return PGFlag(key, NO);
}

void PGSetEnabled(NSString *key, BOOL on) {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:key];
}

NSInteger PGInt(NSString *key, NSInteger fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return value ? [value integerValue] : fallback;
}

void PGSetInt(NSString *key, NSInteger value) {
    [NSUserDefaults.standardUserDefaults setInteger:value forKey:key];
}

NSString *const PGFlagOverridePrefix = @"pureglass.flag.";

id PGFlagOverride(NSString *key) {
    return [NSUserDefaults.standardUserDefaults objectForKey:[PGFlagOverridePrefix stringByAppendingString:key]];
}

void PGSetFlagOverride(NSString *key, id value) {
    key = [PGFlagOverridePrefix stringByAppendingString:key];
    if (value) [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

void PGMigrateKey(NSString *from, NSString *to) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    id value = [store objectForKey:from];
    if (!value || [store objectForKey:to]) return;
    [store setObject:value forKey:to];
    [store removeObjectForKey:from];
}

void PGRestartSpotify(void) {
    [NSUserDefaults.standardUserDefaults synchronize];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
}
