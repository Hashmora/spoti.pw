// Artist redesign: the About card on glass. Spotify draws it as a card painted #282828 with its corners at 16, the
// biography's part of it painted the same again, a gray block on the artist's field (the phone, 2026-10-23). Here
// both paints go and the card is a pane of the sheets' glass with the same corners; the picture at its top stays.
//
// Tree (the phone, 2026-10-23): Creator_ECMKit.CreatorBiographyCardLayout (a private class) 382x452.5, r=16, clips,
// bg #282828, holding the picture and, at its foot, a plain UIView 382x166 bg #282828 with the rank, the name, Follow,
// the listeners and the biography.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static char kAboutGlassKey;

// Spotify's card gray: an opaque neutral between #202020 and #303030.
static BOOL isCardGray(CGColorRef color) {
    if (!color || CGColorGetAlpha(color) < 0.95 || CGColorGetNumberOfComponents(color) < 3) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    return c[0] > 0.12 && c[0] < 0.19 && fabs(c[0] - c[1]) < 0.01 && fabs(c[1] - c[2]) < 0.01;
}

static void dressAbout(UIView *card) {
    if (!card.window || card.bounds.size.width < 1) return;
    SGRGlassPaneIn(card, &kAboutGlassKey, card.layer.cornerRadius > 0 ? card.layer.cornerRadius : 16);
    if (isCardGray(card.layer.backgroundColor)) card.backgroundColor = UIColor.clearColor;
    for (UIView *sub in card.subviews) {
        if (isCardGray(sub.layer.backgroundColor)) sub.backgroundColor = UIColor.clearColor;
    }
}

%ctor {
    if (!SGRedesignedUI()) return;
    Class card = SGRPrivateSwiftClass(@"Creator_ECMKit", @"CreatorBiographyCardLayout");
    if (card) SGRPassView(card, ^(UIView *v) { dressAbout(v); });
    else SGLog(@"class Creator_ECMKit.CreatorBiographyCardLayout not found, the artist's About stays gray");
}
