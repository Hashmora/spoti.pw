// The switches on the mod's own pages (Mod Settings and every page under it) take iOS 26's knob below iOS 26 with the
// legacy glass: white at rest, swelling into glass under a finger (Core/SGGlassThumb.h). Spotify's own switches are left
// as Spotify draws them: a switch counts when a controller of the mod's (SGPage, or any class of the SG prefix) holds it.
#import "Core/SGCore.h"
#import "SGPage.h"

static BOOL onModPage(UIView *view) {
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        if ([r isKindOfClass:SGPage.class] || [NSStringFromClass(r.class) hasPrefix:@"SG"]) return YES;
    }
    return NO;
}

%hook UISwitch
- (void)didMoveToWindow {
    %orig;
    UISwitch *toggle = (UISwitch *)self;
    if (toggle.window && onModPage(toggle)) SGGlassSwitchAttach(toggle);
}
%end

%ctor {
    if (!SGUseLegacyGlass()) return;
    %init;
}
