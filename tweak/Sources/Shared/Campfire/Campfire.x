// Campfire, Spotify's chat, and its row in the side drawer (Campfire_RecentsImpl.RecentChatsSideDrawerItem).
// Whether the feature exists on this account is answered by one object, Campfire_SettingsImpl's
// CampfireFeatureAvailabilityImpl, which the drawer, the chat list and the share sheets all ask. Answering
// yes there lets Spotify build its own Campfire row; the mod draws nothing. The chats themselves still come
// from Spotify's servers.
#import "Core/SGCore.h"

%group Campfire
%hook _TtC21Campfire_SettingsImpl31CampfireFeatureAvailabilityImpl
- (BOOL)isFeatureEnabled { return YES; }
- (BOOL)campfireFeatureEnabled { return YES; }
%end
%end

%ctor {
    %init(Campfire);
    SGRequireClasses(@[@"_TtC21Campfire_SettingsImpl31CampfireFeatureAvailabilityImpl"]);
}
