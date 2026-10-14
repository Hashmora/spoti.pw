// Whether the user follows the page's artist, read from Spotify's collection state (following saves the
// artist to the collection) rather than the Follow button, whose only state is its localized title.
// The provider is the one Spotify's own code uses, kept weakly.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Artist.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>

@protocol SGRCollectionState <NSObject>
+ (id)saved;
- (BOOL)contains:(id)state;
- (NSInteger)rawValue;
@end

@protocol SGRCollectionStateProvider <NSObject>
- (id)subscribeCollectionStateForURL:(NSURL *)url completion:(void (^)(id state, NSError *error))completion;
@end

static __weak id sg_provider;

// Called from wherever Spotify reaches for its provider, any thread.
static void keepProvider(id provider) {
    if (!provider || ![provider respondsToSelector:@selector(subscribeCollectionStateForURL:completion:)]) return;
    static NSMutableSet<NSString *> *logged;
    @synchronized (NSObject.class) {
        if (provider == sg_provider) return;
        sg_provider = provider;
        if (!logged) logged = [NSMutableSet set];
        NSString *name = NSStringFromClass([provider class]);
        if ([logged containsObject:name]) return;
        [logged addObject:name];
    }
    SGLog(@"redesign artist: collection state from %@", NSStringFromClass([provider class]));
}

static __weak id sg_platform;

static id currentProvider(void) {
    id provider;
    @synchronized (NSObject.class) {
        provider = sg_provider;
    }
    if (!provider && [sg_platform respondsToSelector:@selector(stateProvider)]) {
        provider = [sg_platform performSelector:@selector(stateProvider)];
        keepProvider(provider);
    }
    return provider;
}

%hook SPTCollectionPlatformImplementation
- (id)initWithCosmosDataLoader:(id)loader isGatedEntityRelationsEnabled:(BOOL)gated {
    id platform = %orig;
    sg_platform = platform;
    return platform;
}
- (id)stateProvider {
    id provider = %orig;
    keepProvider(provider);
    return provider;
}
%end

%hook _TtC23Collection_PlatformImpl22CollectionPlatformImpl
- (id)stateProvider {
    id provider = %orig;
    keepProvider(provider);
    return provider;
}
%end

%hook _TtC23Collection_PlatformImpl27CollectionPlatformMigration
- (id)stateProvider {
    id provider = %orig;
    keepProvider(provider);
    return provider;
}
%end

%hook _TtC26AlignedCuration_CommonImpl21ACUCollectionPlatform
- (id)stateProvider {
    id provider = %orig;
    keepProvider(provider);
    return provider;
}
%end

%hook _TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl
- (id)subscribeCollectionStateForURL:(id)url completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURLs:(id)urls completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURL:(id)url inContextURL:(id)context completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURLs:(id)urls inContextURL:(id)context completion:(id)completion {
    keepProvider(self);
    return %orig;
}
%end

%hook _TtC26AlignedCuration_CommonImpl25ACUEsperantoStateProvider
- (id)subscribeCollectionStateForURL:(id)url completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURLs:(id)urls completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURL:(id)url inContextURL:(id)context completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURLs:(id)urls inContextURL:(id)context completion:(id)completion {
    keepProvider(self);
    return %orig;
}
%end

// The Follow element asks Curation's provider, which wraps the collection one.
%hook _TtC21Curation_PlatformImpl30CUPStateProviderImplementation
- (id)subscribeCollectionStateForURL:(id)url inContext:(id)context completion:(id)completion {
    Ivar ivar = class_getInstanceVariable(object_getClass(self), "collectionPlatformStateProvider");
    if (ivar) keepProvider(object_getIvar(self, ivar));
    return %orig;
}
%end

#pragma mark - one subscription per page

// Held by the page, so the subscription ends with it.
@interface SGRFollowWatch : NSObject
@property (nonatomic, copy) NSURL *uri;
@property (nonatomic, strong) id token;
@property (nonatomic) BOOL subscribed;
@property (nonatomic) NSInteger following;   // -1 until the first state arrives
@property (nonatomic, copy) void (^changed)(void);
@end

@implementation SGRFollowWatch
- (void)dealloc {
    if ([_token respondsToSelector:@selector(cancel)]) [_token cancel];
}
@end

static char kWatchKey;

// The artist a page URI names after an "artist" component, as spotify:artist:<id>; nil when it names none.
static NSURL *artistInside(NSURL *uri) {
    NSArray<NSString *> *parts = [uri.absoluteString componentsSeparatedByString:@":"];
    NSCharacterSet *other = [NSCharacterSet alphanumericCharacterSet].invertedSet;
    for (NSUInteger i = 0; i + 1 < parts.count; i++) {
        NSString *identifier = parts[i + 1];
        if (![parts[i] isEqualToString:@"artist"] || identifier.length != 22
            || [identifier rangeOfCharacterFromSet:other].location != NSNotFound) continue;
        return [NSURL URLWithString:[@"spotify:artist:" stringByAppendingString:identifier]];
    }
    return nil;
}

// The songs liked by one artist keep the URL they were opened with in a field of their own (pageURL, a Swift URL,
// which is the one object it wraps). Read only from a pointer that is a live allocation.
static NSURL *artistFromPageURL(UIViewController *controller) {
    Class cls = object_getClass(controller);
    Ivar ivar = class_getInstanceVariable(cls, "pageURL");
    ptrdiff_t offset = ivar ? ivar_getOffset(ivar) : 0;
    if (offset <= 0 || (size_t)offset + sizeof(void *) > class_getInstanceSize(cls)) return nil;
    void *raw = *(void **)((char *)(__bridge void *)controller + offset);
    if (!raw || ((uintptr_t)raw & 7) || malloc_size(raw) == 0) return nil;
    id value = (__bridge id)raw;
    if (![value isKindOfClass:NSURL.class]) return nil;
    static BOOL said;
    if (!said) {
        said = YES;
        SGLog(@"redesign artist: the page's own URL is %@", [(NSURL *)value absoluteString]);
    }
    return artistInside(value);
}

// The artist a page's controller names through an accessor of its own, when it has one that gives an object.
static NSURL *artistFromAccessors(UIViewController *controller) {
    NSURL *own = artistFromPageURL(controller);
    if (own) return own;
    for (NSString *name in @[@"artistURI", @"artistURL", @"entityURI", @"contextURI", @"uri", @"URI"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(object_getClass(controller), selector);
        if (!method) continue;
        char *type = method_copyReturnType(method);
        BOOL object = type && type[0] == '@';
        free(type);
        if (!object) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(controller, selector);
        NSString *text = [value isKindOfClass:NSURL.class] ? [value absoluteString] : [value isKindOfClass:NSString.class] ? value : nil;
        NSURL *uri = text ? [NSURL URLWithString:text] : nil;
        if ([text hasPrefix:@"spotify:artist:"]) return uri;
        if (uri && artistInside(uri)) return artistInside(uri);
    }
    return nil;
}

// The artist the page is for. The artist page's controllers carry no URI, but the header's ⋯ does:
// Components.UI.ContextMenuButton-<artist id>.
static NSURL *artistURI(UIView *page, NSString *moreIdentifier) {
    for (UIResponder *responder = page; responder; responder = responder.nextResponder) {
        if (![responder isKindOfClass:UIViewController.class]) continue;
        NSURL *named = artistFromAccessors((UIViewController *)responder);
        if (named) return named;
        if (![responder respondsToSelector:@selector(spt_pageURI)]) continue;
        id uri = [(id)responder performSelector:@selector(spt_pageURI)];
        if (![uri isKindOfClass:NSURL.class]) continue;
        if ([[uri absoluteString] hasPrefix:@"spotify:artist:"]) return uri;
        // The page of the songs liked by one artist names the artist inside its own URI.
        NSURL *inner = artistInside(uri);
        if (inner) return inner;
    }
    NSString *prefix = @"Components.UI.ContextMenuButton-";
    if (![moreIdentifier hasPrefix:prefix]) return nil;
    NSString *identifier = [moreIdentifier substringFromIndex:prefix.length];
    NSCharacterSet *base62 = [NSCharacterSet alphanumericCharacterSet].invertedSet;
    if (identifier.length != 22 || [identifier rangeOfCharacterFromSet:base62].location != NSNotFound) return nil;
    return [NSURL URLWithString:[@"spotify:artist:" stringByAppendingString:identifier]];
}

static void subscribe(SGRFollowWatch *watch, id provider) {
    Class stateClass = NSClassFromString(@"SPTCollectionPlatformState");
    if (![stateClass respondsToSelector:@selector(saved)]) return;
    id saved = [(Class<SGRCollectionState>)stateClass saved];
    __weak SGRFollowWatch *weakWatch = watch;
    NSURL *uri = watch.uri;
    watch.subscribed = YES;
    SGLog(@"redesign artist: follow subscribes for %@ on %@", uri.absoluteString, NSStringFromClass([provider class]));
    watch.token = [(id<SGRCollectionStateProvider>)provider subscribeCollectionStateForURL:uri completion:^(id state, NSError *error) {
        if (error || ![state respondsToSelector:@selector(contains:)]) {
            SGLog(@"redesign artist: follow state for %@ unreadable: %@ %@", uri.absoluteString, [state class], error);
            return;
        }
        NSInteger raw = [state respondsToSelector:@selector(rawValue)] ? [(id<SGRCollectionState>)state rawValue] : -1;
        BOOL following = [(id<SGRCollectionState>)state contains:saved];
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRFollowWatch *current = weakWatch;
            if (!current || current.following == following) return;
            SGLog(@"redesign kit: follow state %ld for %@", (long)raw, uri.absoluteString);
            current.following = following;
            if (current.changed) current.changed();
        });
    }];
}

BOOL SGRArtistFollowing(UIView *page, NSString *moreIdentifier, BOOL *following, void (^changed)(void)) {
    if (!page) return NO;
    SGRFollowWatch *watch = objc_getAssociatedObject(page, &kWatchKey);
    if (!watch) {
        NSURL *uri = artistURI(page, moreIdentifier);
        if (!uri) {
            static __weak UIView *loggedPage;
            if (loggedPage != page) {
                loggedPage = page;
                NSMutableArray *uris = [NSMutableArray array];
                for (UIResponder *r = page; r; r = r.nextResponder) {
                    if ([r isKindOfClass:UIViewController.class]) SGRLogProbeOnce(r, @"follow page");
                    if ([r isKindOfClass:UIViewController.class] && [r respondsToSelector:@selector(spt_pageURI)]) {
                        [uris addObject:[[(id)r performSelector:@selector(spt_pageURI)] description] ?: @"nil"];
                    }
                }
                SGLog(@"redesign artist: follow has no artist URI, more is %@, page URIs %@", moreIdentifier, uris);
            }
            return NO;
        }
        watch = [SGRFollowWatch new];
        watch.uri = uri;
        watch.following = -1;
        objc_setAssociatedObject(page, &kWatchKey, watch, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    watch.changed = changed;
    id provider = watch.subscribed ? nil : currentProvider();
    if (provider) subscribe(watch, provider);
    if (watch.following < 0) return NO;
    if (following) *following = watch.following == 1;
    return YES;
}

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"SPTCollectionPlatformState", @"_TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl"]);
}
