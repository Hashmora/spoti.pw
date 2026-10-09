// Small helpers the now playing files share: Swift classes found by name, and a view put away.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// A Swift class by module and name, under either spelling the runtime knows it by: the mangled one
// (_TtC<n>Module<n>Name) every hook in this tweak is written with, or Module.Name, which is how the trees
// print the AI DJ's classes. nil when neither exists.
static inline Class PGSwiftClass(NSString *module, NSString *name) {
    NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@", (unsigned long)module.length, module, (unsigned long)name.length, name];
    return NSClassFromString(mangled) ?: NSClassFromString([NSString stringWithFormat:@"%@.%@", module, name]);
}

// Alpha 0, no touches, hidden from accessibility, set again on every call: for Spotify's Swift views, which
// are not hidden (an arranged view that hides can trap its stack view) and which put their alpha back.
static inline void PGNowPlayingVanish(UIView *view) {
    if (!view) return;
    if (view.alpha != 0) view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}
