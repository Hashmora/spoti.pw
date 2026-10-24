// Music Haptics > Everywhere, with a jailbreak: the mod's own Music Haptics carried on while Spotify is not in front
// (the home screen, other apps, the lock screen), where iOS plays no haptics for an app in the background. Spotify
// keeps listening to its own sound and hands each tap and each level of the rumble to SpringBoard, which is always in
// front and plays them. The SpringBoard side is an add-on package of its own, Vitrine Haptics (addons/haptics), installed
// once with a package manager on a jailbroken phone: Vitrine's IPA lives in Spotify's sandbox and has no way into
// SpringBoard, so it carries none of it. Everywhere is offered on a jailbroken phone; switched on without the add-on,
// the page says what to install and links to it, and nothing plays behind Spotify until it answers.
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
// Whether Everywhere is offered: on a jailbroken phone, or wherever the add-on has answered.
BOOL SGHapticEverywhereOffered(void);
// Where the add-on is installed from, opened from the page's notice: the releases of Vitrine's repo for now, where the
// add-on's .deb is attached, until it has a package source of its own.
NSString *SGHapticAddonURL(void);
// Posted on the main thread when SpringBoard first answers, for the Vibrations page to show the switch.
extern NSNotificationName const SGHapticRelayAvailableNotification;
// Asks SpringBoard whether it is there; called once at launch.
void SGHapticRelayAsk(void);
// A tap of `intensity` and `sharpness`, 0 to 1, felt now from SpringBoard; nothing without the add-on. Any thread.
void SGHapticRelayTap(float intensity, float sharpness);
// The rumble at `level`, 0 to 1, from now on; 0 stops it. Any thread.
void SGHapticRelayRumble(float level);
