// The AI DJ's player screen drawn the way spoti.pw's redesign draws the ordinary one: previous, play and next
// as bare glyphs, and under them one row of glyphs, Lyrics, Connect, Queue and the DJ button, without the share
// button.
//
// spoti.pw hooks the ordinary player's units (NowPlaying_ModesImpl.PlaybackControlsElementsUnit, FooterElementsUnit)
// and the DJ has units of its own, so none of it reached this screen (trees/continuous/3.txt and 4.txt,
// 2026-10-09): the controls were Spotify's own discs, Connect sat at the leading edge with the device's name,
// the DJ button and a share button at the other end, and there was no lyrics control and no queue one. This is
// that redesign's PlayerControls.x and PlayerFooter.x (the fork's main branch) done again for the DJ's units.
//
// Controls. DJMHeadUnitViewController's view (SPTNowPlayingHeadUnitView 390x88) holds the buttons directly:
// id=SPTNowPlayingPreviousTrackButton and id=SPTNowPlayingNextTrackButton, EncoreButtons with one UIImageView in
// them, and id=SPTNowPlayingPlayButton, the PlayButtonView with the white disc (a UIImageView the size of its
// CondensedButton). The glyphs go inside the buttons, over the images, which go transparent; the buttons keep
// their actions, their disabled look and their accessibility.
//
// Footer. DJMFooterUnitView (390x56) holds four views that are not in a stack: the share button, the DJ button
// (AIDJButtonElement, id=Components.UI.NeffleButtonNowPlayingContainerView), Connect (id=Components.
// ConnectButtonOutputSwitcher, a 19x19 glyph and the device's name in a MarqueeLabel) and an empty one. Spotify has
// no lyrics or queue control down here, so those two are the Kit's glyph buttons. Connect and the DJ button stay
// Spotify's (the device sheet, the DJ set) and are only moved, by a transform: it survives the footer laying
// them out again. The four sit on one row at even steps, the outer two where the ordinary player has Lyrics
// and Queue.
//
// Lyrics: the player's lyrics card holds Spotify's own "Open full screen lyrics" button (id=lyrics-expand-button,
// trees/continuous/3.txt:637-642), which this glyph fires; it is dim for a track whose card has none. The ordinary
// player's lyrics are spoti.pw's own view of the lyrics, which the DJ's units have no room for. Queue opens
// spotify:now-playing:queue, the link the navbar's Queue tab uses.
//
// The row sits lower than Spotify puts it, just over the home indicator, and the controls follow it part of the
// way, as PlayerFooter.x does (issue #54): the footer's view is translated down, and a band over the part that
// hangs out below the bottom stack hands those touches back to it.
#import "Core/PGCore.h"
#import "Redesigned/Kit/PGRKit.h"
#import "Redesigned/NowPlaying/NowPlayingClasses.h"
#import "Shared/Navigation/Links.h"

static const CGFloat kSkipGlyphSize = 32, kPlayGlyphSize = 44, kFooterGlyphSize = 20;
// Where the four footer glyphs sit, as parts of the footer's width: Lyrics, Connect, Queue, the DJ button.
static const CGFloat kSlots[4] = {0.2, 0.4, 0.6, 0.8};
// The DJ button's blue disc is 48pt, a good deal more than the glyphs beside it; drawn this much of that.
static const CGFloat kDJButtonScale = 0.88;
static const CGFloat kGlyphMaxWidth = 30;
// The row's middle this far above the safe area's bottom, and never less than kRowMinBottom above the screen's;
// the controls follow a share of the row's move.
static const CGFloat kRowAboveSafeArea = 20, kRowMinBottom = 34, kControlsShare = 0.3;
// A spinner still up this long after a state change is buffering; and how long the glyph shows what a tap
// asked for before the player's own state is believed.
static const NSTimeInterval kSpinnerCheck = 0.6, kTapTrust = 1.2;

static NSString *const kPlayerScreenIdentifier = @"SPTNowPlayingViewContainerViewController";

static char kPrevKey, kNextKey, kPlayKey, kGlyphKey;
static char kShareKey, kConnectKey, kDJKey, kLyricsKey, kQueueKey, kReachKey, kLyricsFindKey;

static __weak UIView *pg_playView, *pg_controlsHost, *pg_footerHost;
static __weak UIButton *pg_playButton;
static __weak PGRGlyphView *pg_playGlyph;
static __weak PGRGlyphButton *pg_lyricsButton;
static CFTimeInterval pg_tappedUntil;
static BOOL pg_tappedPaused;

#pragma mark - previous, play and next

static PGRGlyphView *glyphFor(UIView *owner, NSString *symbol, CGFloat size) {
    PGRGlyphView *glyph = objc_getAssociatedObject(owner, &kGlyphKey);
    if (!glyph) {
        glyph = [[PGRGlyphView alloc] initWithSymbol:symbol pointSize:size weight:UIImageSymbolWeightRegular];
        objc_setAssociatedObject(owner, &kGlyphKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return glyph;
}

// On top inside `host` and centred by the autoresizing mask as well as here: the unit lays out before the
// buttons in it have a size, so a centre set then is the middle of nothing.
static void keepOnTop(UIView *view, UIView *host) {
    if (view.superview != host) {
        view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                              | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [host addSubview:view];
    } else if (host.subviews.lastObject != view) {
        [host bringSubviewToFront:view];
    }
    view.center = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
}

static void skipGlyph(UIView *host, NSString *identifier, const void *findKey, NSString *symbol) {
    UIView *button = PGRFindByIdentifier(host, identifier, findKey);
    if (!button) return;
    PGRGlyphView *glyph = glyphFor(button, symbol, kSkipGlyphSize);
    for (UIView *sub in button.subviews) {
        if (sub != glyph && [sub isKindOfClass:UIImageView.class]) PGRSuppress(sub);
    }
    keepOnTop(glyph, button);
}

static BOOL spinnerShowing(UIButton *button) {
    for (UIView *sub in button.subviews) {
        if (!sub.hidden && sub.alpha > 0.01 && [NSStringFromClass(sub.class) containsString:@"SpinnerView"]) return YES;
    }
    return NO;
}

static NSString *symbolFor(BOOL paused) {
    return paused ? @"play.fill" : @"pause.fill";
}

static void refreshPlayGlyph(BOOL animated) {
    PGRGlyphView *glyph = pg_playGlyph;
    SPTPlayerState *state = PGPlayerState();
    if (!glyph || !state) return;
    glyph.alpha = spinnerShowing(pg_playButton) ? 0 : 1;
    if (CACurrentMediaTime() < pg_tappedUntil) {
        if (state.isPaused != pg_tappedPaused) return;
        pg_tappedUntil = 0;
    }
    [glyph setSymbol:symbolFor(state.isPaused) animated:animated];
}

// The player's state reaches the glyph a beat after the tap, which read as a slow button, so the glyph turns
// at the touch to the opposite of what it shows and the state settles it after.
static void playTapped(void) {
    PGRGlyphView *glyph = pg_playGlyph;
    if (!glyph || glyph.alpha == 0) return;
    pg_tappedPaused = ![glyph.symbol isEqualToString:@"play.fill"];
    pg_tappedUntil = CACurrentMediaTime() + kTapTrust;
    [glyph setSymbol:symbolFor(pg_tappedPaused) animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTapTrust * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ refreshPlayGlyph(YES); });
}

static void playGlyph(UIView *host) {
    UIView *play = PGRFindByIdentifier(host, @"SPTNowPlayingPlayButton", &kPlayKey);
    // Before the player has reported a state the glyph could only guess, so the disc stays.
    SPTPlayerState *state = PGPlayerState();
    if (!play || !state) return;
    UIButton *button = nil;
    for (UIView *sub in play.subviews) {
        if ([sub isKindOfClass:UIButton.class]) button = (UIButton *)sub;
    }
    UIImageView *disc = nil;
    for (UIView *sub in button.subviews) {
        if ([sub isKindOfClass:UIImageView.class] && CGSizeEqualToSize(sub.bounds.size, button.bounds.size)) disc = (UIImageView *)sub;
    }
    if (!disc) return;
    PGRSuppress(disc);
    // The holder Spotify crossfades a snapshot of the disc in when play turns to pause.
    for (UIView *sub in play.subviews) {
        if (object_getClass(sub) != UIView.class) continue;
        for (UIView *image in sub.subviews) {
            if ([image isKindOfClass:UIImageView.class]) PGRSuppress(image);
        }
    }
    PGRGlyphView *glyph = glyphFor(play, symbolFor(state.isPaused), kPlayGlyphSize);
    keepOnTop(glyph, button);
    pg_playView = play;
    pg_playButton = button;
    pg_playGlyph = glyph;
    refreshPlayGlyph(NO);
}

static void styleControls(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host || host.bounds.size.width < 100) return;
    pg_controlsHost = host;
    skipGlyph(host, @"SPTNowPlayingPreviousTrackButton", &kPrevKey, @"backward.fill");
    skipGlyph(host, @"SPTNowPlayingNextTrackButton", &kNextKey, @"forward.fill");
    playGlyph(host);

    static dispatch_once_t once;
    dispatch_once(&once, ^{ PGLog(@"AI DJ player: glyphs over previous, play and next in %@", NSStringFromClass(host.class)); });
}

#pragma mark - the footer

// The view of `host`'s own that holds `view`.
static UIView *holderIn(UIView *host, UIView *view) {
    for (UIView *v = view; v && v != host; v = v.superview) {
        if (v.superview == host) return v;
    }
    return nil;
}

// Where `point` of `view` is in the host with the holder's own transform left out.
static CGFloat untransformedX(UIView *holder, UIView *view, CGPoint point) {
    CGPoint local = [view convertPoint:point toView:holder];
    return holder.center.x + local.x - CGRectGetMidX(holder.bounds);
}

static void placeHolder(UIView *holder, CGFloat from, CGFloat to, CGFloat scale) {
    CGAffineTransform transform = CGAffineTransformMake(scale, 0, 0, scale, round(to - from), 0);
    if (!CGAffineTransformEqualToTransform(holder.transform, transform)) holder.transform = transform;
}

static UIView *connectGlyphIn(UIView *connect) {
    __block UIView *glyph = nil;
    PGForEachView(connect, ^(UIView *view) {
        if (!glyph && [view isKindOfClass:UIImageView.class] && view.bounds.size.width > 0 && view.bounds.size.width <= kGlyphMaxWidth) glyph = view;
    });
    return glyph;
}

static PGRGlyphButton *glyphButtonIn(UIView *host, const void *key, NSString *symbol, NSString *title, UIColor *tint, void (^tap)(void)) {
    PGRGlyphButton *button = objc_getAssociatedObject(host, key);
    if (!button) {
        button = [PGRGlyphButton buttonWithSymbol:symbol pointSize:kFooterGlyphSize title:title];
        button.glyph.tintColor = tint;
        button.onTap = tap;
        objc_setAssociatedObject(host, key, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (button.superview != host) [host addSubview:button];
    return button;
}

#pragma mark lyrics

static UIView *lyricsExpandButton(UIView *from) {
    UIView *root = nil;
    for (UIView *v = from; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kPlayerScreenIdentifier]) {
            root = v;
            break;
        }
    }
    return PGRFindByIdentifier(root ?: from.window, @"lyrics-expand-button", &kLyricsFindKey);
}

static void refreshLyrics(void) {
    PGRGlyphButton *lyrics = pg_lyricsButton;
    UIView *host = pg_footerHost;
    if (!lyrics || !host) return;
    BOOL has = lyricsExpandButton(host) != nil;
    if (lyrics.enabled != has) lyrics.enabled = has;
}

static void openLyrics(void) {
    UIView *host = pg_footerHost;
    UIView *button = host ? lyricsExpandButton(host) : nil;
    if (button) PGRActivate(button);
}

#pragma mark lower down

// Moved down, the row is drawn partly below the bottom stack it is arranged in, and UIKit does not look into a
// view for a touch outside its bounds. This band over the part that hangs out hands such a touch to the row
// itself, and lets every other one through.
@interface PGRDJFooterReach : UIView
@property (nonatomic, weak) UIView *row;
@end

@implementation PGRDJFooterReach
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *row = self.row;
    if (!row.window || row.alpha < 0.01 || row.hidden) return nil;
    UIView *hit = [row hitTest:[row convertPoint:point fromView:self] withEvent:event];
    return hit == row ? nil : hit;
}
@end

// The arranged view drawn right above `row` in its stack, by where the stack put them.
static UIView *rowAbove(UIView *row) {
    UIView *best = nil;
    CGFloat top = row.center.y - row.bounds.size.height / 2, bestBottom = -CGFLOAT_MAX;
    for (UIView *sibling in row.superview.subviews) {
        if (sibling == row || sibling.hidden || sibling.alpha < 0.01 || sibling.bounds.size.height < 1) continue;
        CGFloat bottom = sibling.center.y + sibling.bounds.size.height / 2;
        if (bottom <= top + 1 && bottom > bestBottom) {
            best = sibling;
            bestBottom = bottom;
        }
    }
    return best;
}

static void lowerRow(UIView *row) {
    UIView *stack = row.superview, *player = stack.superview;
    UIWindow *window = row.window;
    if (![stack isKindOfClass:UIStackView.class] || !player || !window) return;
    // Where the stack put the row, the row's own transform left out, and where it belongs.
    CGFloat middle = [stack convertPoint:row.center toView:player].y;
    CGFloat target = player.bounds.size.height - MAX(window.safeAreaInsets.bottom + kRowAboveSafeArea, kRowMinBottom);
    CGFloat move = MAX(0, round(target - middle));
    CGAffineTransform down = CGAffineTransformMakeTranslation(0, move);
    if (!CGAffineTransformEqualToTransform(row.transform, down)) row.transform = down;

    // Only the controls, and only straight above.
    UIView *above = rowAbove(row);
    BOOL controls = above && [NSStringFromClass(above.class) containsString:@"HeadUnitView"];
    CGAffineTransform follow = CGAffineTransformMakeTranslation(0, controls ? round(move * kControlsShare) : 0);
    if (above && controls && !CGAffineTransformEqualToTransform(above.transform, follow)) above.transform = follow;

    PGRDJFooterReach *reach = objc_getAssociatedObject(row, &kReachKey);
    if (!reach) {
        reach = [PGRDJFooterReach new];
        reach.row = row;
        objc_setAssociatedObject(row, &kReachKey, reach, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (reach.superview != player) [player addSubview:reach];
    CGRect stackFrame = [stack convertRect:stack.bounds toView:player];
    CGRect drawn = [row convertRect:row.bounds toView:player];
    CGFloat from = CGRectGetMaxY(stackFrame);
    CGRect band = CGRectMake(CGRectGetMinX(drawn), from, drawn.size.width, MAX(0, CGRectGetMaxY(drawn) - from));
    if (!CGRectEqualToRect(reach.frame, band)) reach.frame = band;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PGLog(@"AI DJ player: footer row from %.0f to %.0f of %.0f (safe area %.0f), controls %@", middle, middle + move,
              player.bounds.size.height, window.safeAreaInsets.bottom, controls ? @"follow" : @"stay");
    });
}

#pragma mark the row

static void styleFooter(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host || host.bounds.size.width < 100) return;
    pg_footerHost = host;
    CGFloat width = host.bounds.size.width, middleY = CGRectGetMidY(host.bounds);
    BOOL rtl = host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat (^slot)(NSUInteger) = ^CGFloat(NSUInteger i) { return round(width * (rtl ? 1 - kSlots[i] : kSlots[i])); };

    // No share button; its holder goes too, since a view that takes touches swallows them with nothing on it.
    UIView *share = PGRFindByIdentifier(host, @"ShareButtonNowPlayingView", &kShareKey);
    PGNowPlayingVanish(share);
    PGNowPlayingVanish(holderIn(host, share));

    PGRGlyphButton *lyrics = glyphButtonIn(host, &kLyricsKey, @"quote.bubble", @"Lyrics", PGRSecondary(), ^{ openLyrics(); });
    lyrics.bounds = CGRectMake(0, 0, 44, 44);
    lyrics.center = CGPointMake(slot(0), middleY);
    pg_lyricsButton = lyrics;
    refreshLyrics();

    // Connect: the glyph alone, its device name gone, at the second place.
    UIView *connect = PGRFindByIdentifier(host, @"Components.ConnectButtonOutputSwitcher", &kConnectKey);
    UIView *connectHolder = holderIn(host, connect);
    UIView *glyph = connectGlyphIn(connect);
    for (UIView *view = glyph.superview; view && view != connect; view = view.superview) {
        for (UIView *sibling in view.subviews) {
            if ([NSStringFromClass(sibling.class) containsString:@"MarqueeLabel"]) PGNowPlayingVanish(sibling);
        }
    }
    if (connectHolder) {
        UIView *pinned = glyph ?: connect;
        CGFloat from = untransformedX(connectHolder, pinned, CGPointMake(CGRectGetMidX(pinned.bounds), CGRectGetMidY(pinned.bounds)));
        placeHolder(connectHolder, from, slot(1), 1);
    }

    PGRGlyphButton *queue = glyphButtonIn(host, &kQueueKey, @"list.bullet", @"Queue", PGRPrimary(), ^{
        PGOpenSpotifyURI([NSURL URLWithString:@"spotify:now-playing:queue"]);
    });
    queue.bounds = CGRectMake(0, 0, 44, 44);
    queue.center = CGPointMake(slot(2), middleY);

    // The DJ button at the last place. Connect's view reaches a long way to the right of its glyph, so the
    // DJ's goes above it in the stack, or Connect would take its touches.
    UIView *dj = PGRFindByIdentifier(host, @"Components.UI.NeffleButtonNowPlayingContainerView", &kDJKey);
    UIView *djHolder = holderIn(host, dj);
    if (djHolder) {
        placeHolder(djHolder, djHolder.center.x, slot(3), kDJButtonScale);
        NSArray<UIView *> *order = host.subviews;
        if (connectHolder && [order indexOfObject:djHolder] < [order indexOfObject:connectHolder]) [host bringSubviewToFront:djHolder];
    }

    lowerRow(host);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PGLog(@"AI DJ player: footer %.0f wide, lyrics %.0f, connect %@ to %.0f, queue %.0f, DJ %@ to %.0f, share %@", width, slot(0),
              glyph ? @"glyph" : @"button", slot(1), slot(2), djHolder ? @"found" : @"not found", slot(3), share ? @"gone" : @"not found");
    });
}

#pragma mark - state

@interface PGDJPlayerWatcher : NSObject <PGPlayerStateObserver>
@end

@implementation PGDJPlayerWatcher
- (void)playerStateDidChange:(SPTPlayerState *)state {
    // The first state can land after the controls laid out, which left the disc for want of one.
    if (!pg_playGlyph) [pg_controlsHost setNeedsLayout];
    refreshPlayGlyph(YES);
    // Spotify raises its spinner a moment after a state says loading and drops it a moment after, and a new
    // track's lyrics card turns up well after the track does.
    for (NSNumber *delay in @[@(kSpinnerCheck), @1.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            refreshPlayGlyph(YES);
            refreshLyrics();
        });
    }
}
@end

static PGDJPlayerWatcher *pg_djWatcher;

// The action the play button's own UIButton sends. Only the player's button turns the glyph: the sticky
// header and every page with a play button of its own use the same class.
%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)uiButtonTapped {
    %orig;
    if ((UIView *)self != pg_playView) return;
    playTapped();
}
%end

%group PGDJHeadHooks
%hook PGDJHeadUnit
- (void)viewDidLayoutSubviews {
    %orig;
    styleControls((UIViewController *)self);
}
%end
%end

%group PGDJFooterHooks
%hook PGDJFooterUnit
- (void)viewDidLayoutSubviews {
    %orig;
    styleFooter((UIViewController *)self);
}
%end
%end

%ctor {
    if (!PGRedesignedUI()) return;
    %init;
    pg_djWatcher = [PGDJPlayerWatcher new];
    PGAddPlayerStateObserver(pg_djWatcher);

    Class head = PGSwiftClass(@"Endless_DJMusicImpl", @"DJMHeadUnitViewController");
    if (head) {
        %init(PGDJHeadHooks, PGDJHeadUnit = head);
    } else {
        PGLog(@"class DJMHeadUnitViewController not found, the AI DJ controls keep Spotify's own");
    }
    Class footer = PGSwiftClass(@"Endless_DJMusicImpl", @"DJMFooterUnitViewController");
    if (footer) {
        %init(PGDJFooterHooks, PGDJFooterUnit = footer);
    } else {
        PGLog(@"class DJMFooterUnitViewController not found, the AI DJ footer keeps Spotify's own");
    }
    PGRequireClasses(@[@"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView"]);
}
