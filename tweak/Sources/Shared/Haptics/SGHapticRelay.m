#import "SGHapticRelay.h"
#import "Core/SGCore.h"
#import <notify.h>
#import "Core/SGRebind.h"
#import <stdatomic.h>

NSNotificationName const SGHapticRelayAvailableNotification = @"SGHapticRelayAvailableNotification";

static BOOL sg_available;
// The rumble's level as last posted, so an unchanged one is not posted again; -1 before any.
static atomic_int sg_rumbleSent = -1;
static atomic_uint_fast64_t sg_rumbleSentAt;

BOOL SGHapticRelayAvailable(void) {
    return sg_available;
}

static uint64_t sg_installedBuild;

NSURL *SGHapticAddonPackage(void) {
    return [NSBundle.mainBundle URLForResource:@"VitrineHaptics" withExtension:@"deb"];
}

uint64_t SGHapticAddonInstalledBuild(void) {
    return sg_installedBuild;
}

BOOL SGHapticAddonOutdated(void) {
    return sg_available && sg_installedBuild > 0 && sg_installedBuild < kSGRelayAddonBuild && SGHapticAddonPackage();
}

BOOL SGHapticAddonShare(UIView *view) {
    NSURL *package = SGHapticAddonPackage();
    if (!package || !view.window) return NO;
    // Kept while its menu is up: the menu goes when its controller does.
    static UIDocumentInteractionController *share;
    share = [UIDocumentInteractionController interactionControllerWithURL:package];
    share.UTI = @"org.debian.deb-archive";
    share.name = @"Vitrine Haptics";
    CGRect at = CGRectMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds), 1, 1);
    BOOL shown = [share presentOptionsMenuFromRect:at inView:view animated:YES];
    SGLog(@"music haptics: the add-on's .deb handed to the system's Open In (%@)", shown ? @"shown" : @"nothing takes it");
    return shown;
}

BOOL SGHapticEverywhereOffered(void) {
    return sg_available || SGJailbroken();
}

void SGHapticRelayAsk(void) {
    static int token;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        notify_register_dispatch(kSGRelayPong, &token, dispatch_get_main_queue(), ^(int t) {
            uint64_t build = 0;
            if (notify_get_state(t, &build) == NOTIFY_STATUS_OK) sg_installedBuild = build;
            SGHapticRelaySendLockScreen();
            if (sg_available) return;
            sg_available = YES;
            SGLog(@"music haptics: SpringBoard plays them everywhere (the add-on's build %llu, this one carries %d)",
                  (unsigned long long)sg_installedBuild, kSGRelayAddonBuild);
            [NSNotificationCenter.defaultCenter postNotificationName:SGHapticRelayAvailableNotification object:nil];
        });
    });
    notify_post(kSGRelayPing);
}

void SGHapticRelaySendLockScreen(void) {
    notify_post(SGFlag(SGKeyMusicHapticsLockScreen, YES) ? kSGRelayLockOn : kSGRelayLockOff);
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
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    BOOL same = atomic_exchange(&sg_rumbleSent, b) == b;
    // Unchanged, it goes again now and then while it is on, the add-on's sign that Spotify still means it.
    if (same && (b == 0 || now - atomic_load(&sg_rumbleSentAt) < (uint64_t)(kSGRelayRumbleKeepalive * NSEC_PER_SEC))) return;
    atomic_store(&sg_rumbleSentAt, now);
    char name[64];
    snprintf(name, sizeof name, kSGRelayPrefix "rumble.%d", b);
    notify_post(name);
}
