#import "Settings/SGModPage.h"
#import "Privacy.h"

SGModSection *SGPrivacySection(void) {
    return SGSection(@"Privacy", @[
        SGWithSymbol(SGSwitchRow(
            @"Block telemetry",
            @"Answer the analytics endpoints with an empty reply instead of letting the request out",
            SGKeyBlockTelemetry), @"antenna.radiowaves.left.and.right.slash"),
    ]);
}

SGModSection *SGPrivacyCountersSection(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGBlockedLabels()) {
        [counts addObject:SGStatRow(label, ^NSString *{ return @(SGBlockedCount(label)).stringValue; })];
    }
    [counts addObject:SGStatRow(@"Total", ^NSString *{ return @(SGBlockedCount(nil)).stringValue; })];
    [counts addObject:SGActionRow(@"Reset the telemetry counters", @"Start counting from zero",
                                  ^{ SGResetBlocked(); })];
    return SGSection(@"Telemetry blocked so far", counts);
}
