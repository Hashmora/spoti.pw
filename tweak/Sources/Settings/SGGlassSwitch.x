// The switches on the mod's own pages (Mod Settings and every page under it) take iOS 26's switch below iOS 26 with the
// legacy glass: a wider track, and a white thumb that turns into glass under a finger (Core/SGGlassThumb.h). Spotify's own switches are left
// as Spotify draws them: a switch counts when a controller of the mod's (SGPage, or any class of the SG prefix) holds it.
// The sliders there take iOS 26's thumb the same way, the one Speed, Pitch & Reverb's have (SpeedPitchMenu.x): a white
// capsule that swells into glass under a finger.
#import "Core/SGCore.h"
#import "SGPage.h"
#import <objc/runtime.h>

static BOOL onModPage(UIView *view) {
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        if ([r isKindOfClass:SGPage.class] || [NSStringFromClass(r.class) hasPrefix:@"SG"]) return YES;
    }
    return NO;
}

// Speed, Pitch & Reverb's thumb (SpeedPitchMenu.x).
static const CGSize kSliderThumb = {34, 22};
static char kModSliderKey;

%hook UISlider
- (void)didMoveToWindow {
    %orig;
    UISlider *slider = (UISlider *)self;
    if (!slider.window || objc_getAssociatedObject(slider, &kModSliderKey)) return;
    if (!onModPage(slider)) return;
    objc_setAssociatedObject(slider, &kModSliderKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGGlassThumbAttach(slider, kSliderThumb);
}

- (void)layoutSubviews {
    %orig;
    // Again on the owner's passes: a thumb image set again by the page is swapped back (SGGlassThumb.h).
    UISlider *slider = (UISlider *)self;
    if (objc_getAssociatedObject(slider, &kModSliderKey)) SGGlassThumbAttach(slider, kSliderThumb);
}
%end

%hook UISwitch
- (void)didMoveToWindow {
    %orig;
    UISwitch *toggle = (UISwitch *)self;
    if (toggle.window && onModPage(toggle)) SGGlassSwitchAttach(toggle);
}

- (void)layoutSubviews {
    %orig;
    SGGlassSwitchSync((UISwitch *)self, NO);
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    %orig;
    SGGlassSwitchSync((UISwitch *)self, animated);
}

- (void)setEnabled:(BOOL)enabled {
    %orig;
    SGGlassSwitchSync((UISwitch *)self, NO);
}
%end

%ctor {
    if (!SGUseLegacyGlass()) return;
    %init;
}
