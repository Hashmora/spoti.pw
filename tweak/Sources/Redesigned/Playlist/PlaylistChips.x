// Playlist redesign, iOS < 26: the chips over a playlist's first track (the genres of Liked Songs) on glass.
//
// Tree (trees/continuous/1.txt:24-131): a cell of the list holding CollectionSongs_PlaylistImpl's
// CSNestedChipsElement, whose NestedChipsView scrolls a row of Encore ChipViews. The glass is the Kit's
// (Kit/SGRChips.h), the same the chips of Recents have.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"

static BOOL isChipsCell(UIView *cell) {
    for (UIView *sub in cell.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"CSNestedChipsElement"]) return YES;
    }
    return NO;
}

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (void)layoutSubviews {
    %orig;
    UIView *cell = (UIView *)self;
    if (isChipsCell(cell) && SGRPlaylistHeaderOf(cell)) SGRGlassChipsIn(cell);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"_TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell"]);
}
