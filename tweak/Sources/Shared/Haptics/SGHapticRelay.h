// Music Haptics > Everywhere, with a jailbreak: the mod's own Music Haptics carried on while Spotify is not in front
// (the home screen, other apps, the lock screen), where iOS plays no haptics for an app in the background. Spotify
// keeps listening to its own sound and hands each tap and each level of the rumble to SpringBoard, which is always in
// front and plays them; the .deb's second library, VitrineHaptics (tweak/SpringBoard/HapticRelay.x), is the
// SpringBoard side. An IPA put on a jailbroken phone has no way into SpringBoard: there Spotify plays them itself in
// the background through the system's vibration (AudioServicesPlaySystemSoundWithVibration, the vibration an app that
// is playing sound can still ask for behind other apps; not yet confirmed on the phone), short pulses of the tap's or the rumble's strength, coarser than
// Core Haptics. Everywhere shows on a jailbroken phone either way.
//
// The two talk by Darwin notifications, which a sandboxed app may post and which carry no payload: the value is in the
// name. A tap is one of kSGRelayLevels intensities times kSGRelaySharpnesses sharpnesses, the rumble one of
// kSGRelayLevels levels or 0 for quiet. Spotify posts each at the moment it is to be felt, so SpringBoard plays it at
// once. Spotify asks whether SpringBoard is there with a ping; SpringBoard answers with a pong, and posts one as it
// starts too, so whichever comes up second is heard.
//
// Threading: the posts are made from any thread; the answer is taken on the main queue.
#import <Foundation/Foundation.h>

#define kSGRelayPrefix "com.vitrine.haptics."
#define kSGRelayPing kSGRelayPrefix "ping"
#define kSGRelayPong kSGRelayPrefix "pong"
// kSGRelayPrefix "tap.<1...kSGRelayLevels>.<0...kSGRelaySharpnesses-1>" and kSGRelayPrefix "rumble.<0...kSGRelayLevels>".
enum { kSGRelayLevels = 10, kSGRelaySharpnesses = 3 };

// The key of the switch, off until switched on.
#define SGKeyMusicHapticsEverywhere @"spotifyglass.haptics.music.everywhere"

// Whether SpringBoard's side has answered in this launch. Main thread.
BOOL SGHapticRelayAvailable(void);
// Whether Everywhere can play: SpringBoard's side answered, or the phone is jailbroken and the vibration stands in.
BOOL SGHapticEverywhereAvailable(void);
// Posted on the main thread when SpringBoard first answers, for the Vibrations page to show the switch.
extern NSNotificationName const SGHapticRelayAvailableNotification;
// Asks SpringBoard whether it is there; called once at launch.
void SGHapticRelayAsk(void);
// A tap of `intensity` and `sharpness`, 0 to 1, felt now, from SpringBoard or the vibration. Any thread.
void SGHapticRelayTap(float intensity, float sharpness);
// The rumble at `level`, 0 to 1, from now on; 0 stops it. Any thread.
void SGHapticRelayRumble(float level);
