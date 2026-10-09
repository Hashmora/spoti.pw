// Player: glass behind the header's two round buttons, close (now-playing-minimize-button) and more
// (id=Context menu), on the player and on the AI DJ screen.
//
// With spoti.pw's redesign on, each of the two carries a plain grey UIVisualEffectView 44x44 of spoti.pw's at
// {2, 2} (trees/continuous/1.txt, 2026-10-09, lines 126-129 and 147-150). The circle here is the same size and
// goes in the same place, first in the button's subviews, so PGRGlassInside takes that grey pane out for
// good (PGREvictTwinPanes) and the glass is the only circle drawn. It is a subview of the button, so it
// goes wherever Spotify's row puts the button and the button keeps its actions and its accessibility. The
// AI DJ screen is spoti.pw's own redesign's blind spot: its header buttons (DJMHeaderElementsUnitViewController,
// the same two identifiers) had no circle at all (trees/continuous/3.txt:131-148).
#import "Core/PGCore.h"
#import "Redesigned/Kit/PGRKit.h"
#import "Redesigned/NowPlaying/NowPlayingClasses.h"

static char kGlassKey, kCloseKey, kMoreKey;

static void glassButtons(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    UIView *close = PGRFindByIdentifier(host, @"now-playing-minimize-button", &kCloseKey);
    UIView *more = PGRFindByIdentifier(host, @"Context menu", &kMoreKey);
    if (close) PGRGlassInside(close, &kGlassKey, PGRGlassCircleSize);
    if (more) PGRGlassInside(more, &kGlassKey, PGRGlassCircleSize);

    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *name = NSStringFromClass(unit.class);
    if ([logged containsObject:name]) return;
    [logged addObject:name];
    PGLog(@"player header: glass behind %@ and %@ in %@", close ? @"close" : @"(no close)", more ? @"more" : @"(no more)", name);
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    glassButtons((UIViewController *)self);
}
%end

%group PGDJHeaderHooks
%hook PGDJHeaderUnit
- (void)viewDidLayoutSubviews {
    %orig;
    glassButtons((UIViewController *)self);
}
%end
%end

%ctor {
    if (!PGRedesignedUI()) return;
    %init;
    Class dj = PGSwiftClass(@"Endless_DJMusicImpl", @"DJMHeaderElementsUnitViewController");
    if (dj) {
        %init(PGDJHeaderHooks, PGDJHeaderUnit = dj);
    } else {
        PGLog(@"class DJMHeaderElementsUnitViewController not found, the AI DJ header keeps no glass");
    }
    PGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit"]);
}
