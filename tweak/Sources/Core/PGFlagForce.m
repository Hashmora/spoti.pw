#import <os/lock.h>
#import "PGFlagForce.h"
#import "PGPrefs.h"

@interface PGFlagForcerEntry : NSObject
@property (nonatomic) BOOL beatsOverride;
@property (nonatomic, copy) PGFlagForcer atLaunch, locked;
@end

@implementation PGFlagForcerEntry
@end

// Swapped whole under the lock, so a reader walks an immutable array.
static os_unfair_lock pg_lock = OS_UNFAIR_LOCK_INIT;
static NSArray<PGFlagForcerEntry *> *pg_forcers;

void PGRegisterFlagForcer(BOOL beatsOverride, PGFlagForcer atLaunch, PGFlagForcer locked) {
    if (!atLaunch) return;
    PGFlagForcerEntry *entry = [PGFlagForcerEntry new];
    entry.beatsOverride = beatsOverride;
    entry.atLaunch = atLaunch;
    entry.locked = locked;
    os_unfair_lock_lock(&pg_lock);
    pg_forcers = [(pg_forcers ?: @[]) arrayByAddingObject:entry];
    os_unfair_lock_unlock(&pg_lock);
}

static NSArray<PGFlagForcerEntry *> *forcers(void) {
    os_unfair_lock_lock(&pg_lock);
    NSArray *list = pg_forcers;
    os_unfair_lock_unlock(&pg_lock);
    return list;
}

id PGForcedFlagValue(NSString *key) {
    if (!key) return nil;
    NSArray<PGFlagForcerEntry *> *list = forcers();
    for (PGFlagForcerEntry *entry in list) {
        if (!entry.beatsOverride) continue;
        id value = entry.atLaunch(key);
        if (value) return value;
    }
    id value = PGFlagOverride(key);
    if (value) return value;
    for (PGFlagForcerEntry *entry in list) {
        if (entry.beatsOverride) continue;
        value = entry.atLaunch(key);
        if (value) return value;
    }
    return nil;
}

id PGLockedFlagValue(NSString *key, BOOL *beatsOverride) {
    if (beatsOverride) *beatsOverride = NO;
    if (!key) return nil;
    NSArray<PGFlagForcerEntry *> *list = forcers();
    for (int pass = 0; pass < 2; pass++) {
        BOOL first = pass == 0;
        for (PGFlagForcerEntry *entry in list) {
            if (entry.beatsOverride != first || !entry.locked) continue;
            id value = entry.locked(key);
            if (!value) continue;
            if (beatsOverride) *beatsOverride = first;
            return value;
        }
    }
    return nil;
}
