// Player redesign, iOS < 26: the background of the Speed, Pitch & Reverb panel (SGPlayerShowSpeedPitchPanel), a
// popover from the ⋯. On iOS 26 the system gives the popover Liquid Glass, as it does the ⋯ menu it comes from. Below
// it the popover is a plain blur while the menu wears the mod's glass (ContextMenu/ContextMenuGlass.x), so the panel
// would open from the glass as a different material. UIPopoverBackgroundView is UIKit's public way to draw a
// popover's chrome: this one is the menu's pane (SGRMenuGlass), with no arrow, as the menu has none.
//
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/ContextMenu/ContextMenu.h"
#import "Shared/Player/SpeedPitch.h"

static char kPanelGlassKey;

@interface SGRPanelBackground : UIPopoverBackgroundView
@end

@implementation SGRPanelBackground {
    UIPopoverArrowDirection _arrowDirection;
    CGFloat _arrowOffset;
}

// Both properties are the subclass's to keep. The arrow is not drawn.
- (UIPopoverArrowDirection)arrowDirection { return _arrowDirection; }
- (void)setArrowDirection:(UIPopoverArrowDirection)direction { _arrowDirection = direction; }
- (CGFloat)arrowOffset { return _arrowOffset; }
- (void)setArrowOffset:(CGFloat)offset { _arrowOffset = offset; }

+ (CGFloat)arrowHeight { return 0; }
+ (CGFloat)arrowBase { return 0; }
+ (UIEdgeInsets)contentViewInsets { return UIEdgeInsetsZero; }
+ (BOOL)wantsDefaultContentAppearance { return NO; }

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    // Glass takes the appearance it inherits, which on a phone in light mode is light.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    SGRMenuGlass(self, &kPanelGlassKey);
}
@end

Class SGPlayerPanelBackgroundClass(void) {
    if (!SGRedesignedUI() || !SGBelowiOS26()) return nil;
    return SGRPanelBackground.class;
}
