// A slider's thumb as iOS 26 draws it, below iOS 26 with the legacy glass: a solid white capsule at rest that
// swells into clear glass while a finger holds it, pulled out past the ends of the track on a rubber band, with a
// tap of the Taptic Engine as it meets an end. The slider stays the caller's: UIKit's (Speed and Pitch), the system
// volume's, Spotify's progress. Only its thumb is drawn here.
//
// The thumb image is swapped for a clear one of `size` (so UIKit places the thumb by it) and the capsule goes into the
// view UIKit draws the thumb with, so it moves with the thumb and needs no pass of its own. A thumb image set again by
// the slider's owner is swapped back on the next call.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Gives `slider` the glass thumb, a capsule of `size` at rest. Nothing when the legacy glass is not in use (iOS 26
// draws its own; a plain blur has nothing to swell into). Idempotent: call it from the owner's layout passes.
void SGGlassThumbAttach(UISlider *slider, CGSize size);

// The same for a switch's knob: UIKit's white knob while the switch is left alone, and, while a finger holds it, the
// capsule swelling into clear glass and sliding to the side the finger is on, then back into the white knob where the
// switch settles. Nothing when the legacy glass is not in use. Idempotent.
void SGGlassSwitchAttach(UISwitch *toggle);
