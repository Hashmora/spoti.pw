#import <os/lock.h>
#import "Core/PGCore.h"
#import "PGRedesign.h"

// Written from the constructors, read by the configuration provider on whatever thread it asks from;
// the lock only guards the swap of the immutable table.
static os_unfair_lock pg_flagsLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary<NSString *, id> *pg_flags;

static id forcedNow(NSString *key) {
    os_unfair_lock_lock(&pg_flagsLock);
    id value = pg_flags[key];
    os_unfair_lock_unlock(&pg_flagsLock);
    return value;
}

void PGRedesignForceFlags(NSString *owner, NSDictionary<NSString *, id> *flags) {
    if (!flags.count) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PGRegisterFlagForcer(YES, ^id(NSString *key) { return PGRedesignedUI() ? forcedNow(key) : nil; },
                             ^id(NSString *key) { return PGRedesignedUIStored() ? forcedNow(key) : nil; });
    });
    os_unfair_lock_lock(&pg_flagsLock);
    NSMutableDictionary *all = [pg_flags mutableCopy] ?: [NSMutableDictionary dictionary];
    [all addEntriesFromDictionary:flags];
    pg_flags = [all copy];
    os_unfair_lock_unlock(&pg_flagsLock);
    if (!PGRedesignedUI()) return;
    PGLog(@"redesign %@: forcing %lu flags", owner, (unsigned long)flags.count);
    [flags enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        id override = PGFlagOverride(key);
        if (override) PGLog(@"redesign %@: flag %@ forced %@ over the All flags override %@", owner, key, value, override);
    }];
}
