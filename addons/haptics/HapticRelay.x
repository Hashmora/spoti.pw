// Vitrine Haptics, an add-on package of its own for a jailbroken phone, loaded into SpringBoard: it plays the taps and
// the rumble Spotify's Music Haptics hands it while Spotify is not in front (tweak/Sources/Shared/Haptics/SGHapticRelay.h,
// which names the notifications), since iOS plays haptics for SpringBoard at any time and for an app in the background
// never. Vitrine itself (its IPA or its .deb) does not carry it: it is installed once with a package manager.
//
// Each name is registered once and played the moment it is posted: a tap is a transient of its intensity and
// sharpness, the rumble one looping continuous event whose intensity control follows the level it is posted at, and
// stopped at 0. It answers Spotify's ping with a pong, and posts one as it starts, so Spotify hears it whichever
// came up first.
//
// Threading: the notifications and Core Haptics on one serial queue of its own.
#import <CoreHaptics/CoreHaptics.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import "../../tweak/Sources/Shared/Haptics/SGHapticRelay.h"

// The rumble's loop, as Spotify's own (MusicHaptics.x: kRumbleLength), restarted by its loop for as long as it plays.
static const NSTimeInterval kRumbleLength = 30;

static dispatch_queue_t sg_queue;
static CHHapticEngine *sg_engine;
static id<CHHapticAdvancedPatternPlayer> sg_rumble;
static BOOL sg_rumbling;

static BOOL engineUp(void) {
    if (!CHHapticEngine.capabilitiesForHardware.supportsHaptics) return NO;
    NSError *error = nil;
    if (!sg_engine) {
        sg_engine = [[CHHapticEngine alloc] initAndReturnError:&error];
        if (!sg_engine) return NO;
        sg_engine.playsHapticsOnly = YES;
        sg_engine.autoShutdownEnabled = YES;
        sg_engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
            dispatch_async(sg_queue, ^{
                sg_rumble = nil;
                sg_rumbling = NO;
            });
        };
        sg_engine.resetHandler = ^{
            dispatch_async(sg_queue, ^{
                sg_rumble = nil;
                sg_rumbling = NO;
                [sg_engine startAndReturnError:nil];
            });
        };
    }
    return [sg_engine startAndReturnError:&error];
}

static CHHapticEventParameter *parameter(CHHapticEventParameterID identifier, float value) {
    return [[CHHapticEventParameter alloc] initWithParameterID:identifier value:value];
}

static void tap(float intensity, float sharpness) {
    if (!engineUp()) return;
    CHHapticEvent *hit = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient parameters:@[
        parameter(CHHapticEventParameterIDHapticIntensity, intensity),
        parameter(CHHapticEventParameterIDHapticSharpness, sharpness),
    ] relativeTime:0];
    CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[hit] parameters:@[] error:nil];
    id<CHHapticPatternPlayer> player = pattern ? [sg_engine createPlayerWithPattern:pattern error:nil] : nil;
    [player startAtTime:CHHapticTimeImmediate error:nil];
}

static void rumble(float level) {
    if (level <= 0) {
        if (sg_rumbling) [sg_rumble stopAtTime:CHHapticTimeImmediate error:nil];
        sg_rumbling = NO;
        return;
    }
    if (!engineUp()) return;
    if (!sg_rumble) {
        CHHapticEvent *hum = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous parameters:@[
            parameter(CHHapticEventParameterIDHapticIntensity, 1),
            parameter(CHHapticEventParameterIDHapticSharpness, 0),
        ] relativeTime:0 duration:kRumbleLength];
        CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[hum] parameters:@[] error:nil];
        sg_rumble = pattern ? [sg_engine createAdvancedPlayerWithPattern:pattern error:nil] : nil;
        sg_rumble.loopEnabled = YES;
        if (!sg_rumble) return;
    }
    CHHapticDynamicParameter *control = [[CHHapticDynamicParameter alloc] initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl
                                                                                         value:level relativeTime:0];
    [sg_rumble sendParameters:@[control] atTime:CHHapticTimeImmediate error:nil];
    if (!sg_rumbling) sg_rumbling = [sg_rumble startAtTime:CHHapticTimeImmediate error:nil];
}

static void listen(const char *name, void (^handler)(void)) {
    int token;
    notify_register_dispatch(name, &token, sg_queue, ^(int t) { handler(); });
}

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    sg_queue = dispatch_queue_create("com.vitrine.haptics", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
    for (int level = 1; level <= kSGRelayLevels; level++) {
        for (int sharp = 0; sharp < kSGRelaySharpnesses; sharp++) {
            char name[64];
            snprintf(name, sizeof name, kSGRelayPrefix "tap.%d.%d", level, sharp);
            float intensity = (float)level / kSGRelayLevels, sharpness = (sharp + 0.5f) / kSGRelaySharpnesses;
            listen(name, ^{ tap(intensity, sharpness); });
        }
    }
    for (int level = 0; level <= kSGRelayLevels; level++) {
        char name[64];
        snprintf(name, sizeof name, kSGRelayPrefix "rumble.%d", level);
        float value = (float)level / kSGRelayLevels;
        listen(name, ^{ rumble(value); });
    }
    listen(kSGRelayPing, ^{ notify_post(kSGRelayPong); });
    notify_post(kSGRelayPong);
}
