#import "SGHapticRelay.h"
#import "Core/SGCore.h"
#import <notify.h>
#import "Core/SGRebind.h"
#import "Settings/SGPageStyle.h"
#import <stdatomic.h>

NSNotificationName const SGHapticRelayAvailableNotification = @"SGHapticRelayAvailableNotification";

static BOOL sg_available;
// The rumble's level as last posted, so an unchanged one is not posted again; -1 before any.
static atomic_int sg_rumbleSent = -1;

BOOL SGHapticRelayAvailable(void) {
    return sg_available;
}

NSString *SGHapticAddonURL(void) {
    return [SGRepoURL stringByAppendingString:@"/releases"];
}

BOOL SGHapticEverywhereOffered(void) {
    return sg_available || SGJailbroken();
}

void SGHapticRelayAsk(void) {
    static int token;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        notify_register_dispatch(kSGRelayPong, &token, dispatch_get_main_queue(), ^(int t) {
            if (sg_available) return;
            sg_available = YES;
            SGLog(@"music haptics: SpringBoard plays them everywhere");
            [NSNotificationCenter.defaultCenter postNotificationName:SGHapticRelayAvailableNotification object:nil];
        });
    });
    notify_post(kSGRelayPing);
}

static int bucket(float value, int count) {
    int b = (int)lroundf(MAX(0, MIN(1, value)) * count);
    return MAX(0, MIN(count, b));
}

void SGHapticRelayTap(float intensity, float sharpness) {
    if (!sg_available) return;
    int level = MAX(1, bucket(intensity, kSGRelayLevels));
    int sharp = MIN(kSGRelaySharpnesses - 1, (int)(MAX(0, MIN(1, sharpness)) * kSGRelaySharpnesses));
    char name[64];
    snprintf(name, sizeof name, kSGRelayPrefix "tap.%d.%d", level, sharp);
    notify_post(name);
}

void SGHapticRelayRumble(float level) {
    int b = bucket(level, kSGRelayLevels);
    if (!sg_available) return;
    if (atomic_exchange(&sg_rumbleSent, b) == b) return;
    char name[64];
    snprintf(name, sizeof name, kSGRelayPrefix "rumble.%d", b);
    notify_post(name);
}
