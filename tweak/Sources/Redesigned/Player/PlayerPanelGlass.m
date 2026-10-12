// Player redesign, iOS < 26: the glass of the Speed, Pitch & Reverb panel (SGPlayerShowSpeedPitchPanel), a popover
// from the ⋯. On iOS 26 the system gives the popover Liquid Glass, as it does the ⋯ menu it comes from. Below it the
// popover is a plain blur while the menu wears the mod's glass (ContextMenu/ContextMenuGlass.x), so the panel would
// open from the glass as a different material.
//
// The popover stays the system's, so its animation does too (a background class of the mod's own took it away): its
// blur, found among the views above the panel's, is hidden and the menu's pane (SGRMenuGlass) goes in beside it. If
// no blur is found, nothing is changed.
//
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/ContextMenu/ContextMenu.h"
#import "Shared/Player/SpeedPitch.h"

// The black over the pane: lighter than the menu's, whose rows are long white labels; the panel is sliders.
static const CGFloat kPanelDim = 0.18;
static char kPanelGlassKey;

// The ancestor of `content` that holds the popover's own blur, nearest first.
static UIView *chromeAbove(UIView *content) {
    UIView *host = content.superview;
    for (int depth = 0; host && depth < 4; depth++, host = host.superview) {
        for (UIView *sub in host.subviews) {
            if (![sub isKindOfClass:UIVisualEffectView.class]) continue;
            if (objc_getAssociatedObject(host, &kPanelGlassKey) == sub) continue;
            return host;
        }
    }
    return nil;
}

void SGPlayerStylePanel(UIView *content) {
    if (!SGRedesignedUI() || !SGBelowiOS26() || !content.window) return;
    UIView *host = chromeAbove(content);
    if (!host) {
        static int logged;
        if (logged++ < 2) SGLog(@"speed and pitch: no blur above the panel, its popover keeps the system's");
        return;
    }
    UIView *glass = SGRMenuGlass(host, &kPanelGlassKey, kPanelDim);
    for (UIView *sub in host.subviews) {
        if (sub != glass && [sub isKindOfClass:UIVisualEffectView.class] && !sub.hidden) sub.hidden = YES;
    }
}
