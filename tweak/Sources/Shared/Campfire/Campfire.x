// Campfire, Spotify's chat, and its row in the side drawer (Campfire_RecentsImpl.RecentChatsSideDrawerItem).
// Whether the feature exists on this account is answered by one object, Campfire_SettingsImpl's
// CampfireFeatureAvailabilityImpl, which the drawer, the chat list and the share sheets all ask. Answering
// yes there lets Spotify build its own Campfire row; the mod draws nothing. The chats themselves still come
// from Spotify's servers.
//
// The object also holds some sixty smaller switches (photos, receipts, group chats...), each a remote-config
// flag that Spotify's servers set per account and market. The first time it is asked, the mod logs which of
// them are on and off, as Spotify gave them, so two accounts can be compared (make log | grep campfire).
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"

static void logSwitches(id object, BOOL feature) {
    NSMutableArray<NSString *> *on = [NSMutableArray array];
    NSMutableArray<NSString *> *off = [NSMutableArray array];
    unsigned count = 0;
    Method *methods = class_copyMethodList(object_getClass(object), &count);
    for (unsigned i = 0; i < count; i++) {
        if (method_getNumberOfArguments(methods[i]) != 2) continue;
        char *type = method_copyReturnType(methods[i]);
        BOOL isBool = type && strcmp(type, "B") == 0;
        free(type);
        if (!isBool) continue;
        SEL selector = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(selector);
        if ([name isEqualToString:@"isFeatureEnabled"] || [name isEqualToString:@"campfireFeatureEnabled"]) continue;
        BOOL value = ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
        [value ? on : off addObject:name];
    }
    free(methods);
    SGLog(@"campfire: Spotify's own isFeatureEnabled=%d", feature);
    SGLog(@"campfire: %lu switches off: %@", (unsigned long)off.count, [off componentsJoinedByString:@" "]);
    SGLog(@"campfire: %lu switches on: %@", (unsigned long)on.count, [on componentsJoinedByString:@" "]);
}

%group Campfire
%hook _TtC21Campfire_SettingsImpl31CampfireFeatureAvailabilityImpl
- (BOOL)isFeatureEnabled {
    static BOOL logged;
    if (!logged) {
        logged = YES;
        logSwitches(self, %orig);
    }
    return YES;
}
- (BOOL)campfireFeatureEnabled { return YES; }
%end
%end

%ctor {
    %init(Campfire);
    SGRequireClasses(@[@"_TtC21Campfire_SettingsImpl31CampfireFeatureAvailabilityImpl"]);
}
