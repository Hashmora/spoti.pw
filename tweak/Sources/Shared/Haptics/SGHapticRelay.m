#import "SGHapticRelay.h"
#import "Core/SGCore.h"
#import <dlfcn.h>
#import <notify.h>
#import "Core/SGRebind.h"
#import <stdatomic.h>

NSNotificationName const SGHapticRelayAvailableNotification = @"SGHapticRelayAvailableNotification";

static BOOL sg_available;
// The rumble's level as last posted, so an unchanged one is not posted again; -1 before any.
static atomic_int sg_rumbleSent = -1;

BOOL SGHapticRelayAvailable(void) {
    return sg_available;
}

BOOL SGHapticEverywhereAvailable(void) {
    return sg_available || SGJailbroken();
}

// The vibration that stands in without SpringBoard's side: AudioToolbox's private call, which takes a pattern of on and
// off times in milliseconds and an intensity. Found once; nil leaves the taps unplayed.
typedef void (*SGVibrate)(UInt32 sound, id unused, NSDictionary *pattern);
static SGVibrate vibration(void) {
    static SGVibrate found;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        found = (SGVibrate)dlsym(RTLD_DEFAULT, "AudioServicesPlaySystemSoundWithVibration");
        SGLog(@"music haptics: the system's vibration %@", found ? @"stands in for SpringBoard" : @"is not there");
    });
    return found;
}

// A pulse of `ms` at `intensity`; 4095 is kSystemSoundID_Vibrate.
static void vibrate(float intensity, int ms) {
    SGVibrate play = vibration();
    if (!play || intensity <= 0) return;
    play(4095, nil, @{@"VibePattern": @[@YES, @(ms)], @"Intensity": @(MAX(0.05f, MIN(1, intensity)))});
}

// The rumble without SpringBoard: a pulse of its level each time it is set, no closer together than this, each as long.
static const int kRumblePulse = 60;
static atomic_uint_fast64_t sg_rumblePulsedAt;

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
    if (!sg_available) {
        vibrate(intensity, 25 + (int)(15 * (1 - sharpness)));
        return;
    }
    int level = MAX(1, bucket(intensity, kSGRelayLevels));
    int sharp = MIN(kSGRelaySharpnesses - 1, (int)(MAX(0, MIN(1, sharpness)) * kSGRelaySharpnesses));
    char name[64];
    snprintf(name, sizeof name, kSGRelayPrefix "tap.%d.%d", level, sharp);
    notify_post(name);
}

void SGHapticRelayRumble(float level) {
    int b = bucket(level, kSGRelayLevels);
    if (!sg_available) {
        uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        if (b == 0 || now - atomic_load(&sg_rumblePulsedAt) < (uint64_t)kRumblePulse * NSEC_PER_MSEC) return;
        atomic_store(&sg_rumblePulsedAt, now);
        vibrate(0.6f * b / kSGRelayLevels, kRumblePulse);
        return;
    }
    if (atomic_exchange(&sg_rumbleSent, b) == b) return;
    char name[64];
    snprintf(name, sizeof name, kSGRelayPrefix "rumble.%d", b);
    notify_post(name);
}
