// PlayerState.h names the hooks and why they are the ones.
#import "Core/PGCore.h"
#import "PlayerState.h"

NSString *PGURIString(id uri) {
    if ([uri isKindOfClass:NSString.class]) return uri;
    if ([uri isKindOfClass:NSURL.class]) return ((NSURL *)uri).absoluteString;
    return nil;
}

static NSHashTable<id<PGPlayerStateObserver>> *pg_stateObservers;
static SPTPlayerState *pg_playerState;
static NSString *pg_stateKey;
// Set once the now playing platform has reported; the mod's own observer on the player stands down.
static BOOL pg_platformReported = NO;

void PGAddPlayerStateObserver(id<PGPlayerStateObserver> observer) {
    if (!observer) return;
    if (!pg_stateObservers) pg_stateObservers = [NSHashTable weakObjectsHashTable];
    [pg_stateObservers addObject:observer];
}

SPTPlayerState *PGPlayerState(void) {
    return pg_playerState;
}

// What an observer is told about; the state object itself is new with every position report.
static NSString *keyOf(SPTPlayerState *state) {
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    BOOL shuffling = [options respondsToSelector:@selector(shufflingContext)] && options.shufflingContext;
    return [NSString stringWithFormat:@"%@|%@|%d%d%d%d", PGURIString(state.track.URI), PGURIString(state.contextURI),
            state.isPaused, state.isPlaying, [state respondsToSelector:@selector(isLoading)] && state.isLoading, shuffling];
}

static void publish(SPTPlayerState *state) {
    pg_playerState = state;
    NSString *key = keyOf(state);
    if ([key isEqualToString:pg_stateKey]) return;
    pg_stateKey = key;
    for (id<PGPlayerStateObserver> observer in pg_stateObservers.allObjects) [observer playerStateDidChange:state];
}

static void report(id state, BOOL platform) {
    if (![state isKindOfClass:objc_getClass("SPTPlayerState")]) return;
    dispatch_block_t apply = ^{
        if (platform) pg_platformReported = YES;
        else if (pg_platformReported) return;
        publish(state);
    };
    if (NSThread.isMainThread) apply();
    else dispatch_async(dispatch_get_main_queue(), apply);
}

@interface PGPlayerObserver : NSObject
@end

@implementation PGPlayerObserver
- (void)player:(id)player stateDidChange:(id)state {
    report(state, NO);
}
@end

static PGPlayerObserver *pg_ownObserver;

%hook _TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation
- (void)player:(id)player stateDidChange:(id)state {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PGLog(@"player state: from %@, a %@, on the main thread %d", [player class], [state class], NSThread.isMainThread);
    });
    report(state, YES);
}
%end

// Observers are added from several threads as the app starts; the first player seen is the one
// watched, the way KaraokeSource.x takes the first player the app asks.
%hook SPTEsperantoPlayer
- (void)addPlayerObserver:(id)observer {
    %orig;
    id player = self;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            pg_ownObserver = [PGPlayerObserver new];
            [(id<SPTPlayer>)player addPlayerObserver:pg_ownObserver];
            id state = [player respondsToSelector:@selector(state)] ? [(id<SPTPlayer>)player state] : nil;
            if (state) report(state, NO);
        });
    });
}
%end

%ctor {
    %init;
    PGRequireClasses(@[@"_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation", @"SPTEsperantoPlayer", @"SPTPlayerState"]);
}
