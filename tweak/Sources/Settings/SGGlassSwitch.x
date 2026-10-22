// The switches on the mod's own pages (Mod Settings and every page under it) take iOS 26's switch below iOS 26 with the
// legacy glass: a wider track, and a white thumb that turns into glass under a finger (Core/SGGlassThumb.h). Spotify's own switches are left
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
