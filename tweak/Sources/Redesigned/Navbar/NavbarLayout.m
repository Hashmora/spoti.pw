// The saved composition of the redesign's bar, as NSUserDefaults property lists, apart from the native look's.
#import "Navbar.h"
#import "Shared/Navigation/Links.h"

NSString *const PGRNavbarID = @"id";
NSString *const PGRNavbarTitle = @"title";
NSString *const PGRNavbarURI = @"uri";
NSString *const PGRNavbarIcon = @"icon";
NSString *const PGRNavbarHidden = @"hidden";

static NSString *const kNavbarLayout = @"pureglass.redesign.navbar.layout";
static NSString *const kNavbarStock = @"pureglass.redesign.navbar.stock";

// Only property list types go in, so a corrupt read cannot be anything but an array of dictionaries.
static NSArray *listOfKind(NSString *key, Class kind) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:key];
    for (id item in list) if (![item isKindOfClass:kind]) return @[];
    return list ?: @[];
}

NSArray<NSDictionary *> *PGRNavbarLayout(void) {
    return listOfKind(kNavbarLayout, NSDictionary.class);
}

void PGRSetNavbarLayout(NSArray<NSDictionary *> *layout) {
    [NSUserDefaults.standardUserDefaults setObject:layout ?: @[] forKey:kNavbarLayout];
}

NSArray<NSString *> *PGRNavbarStock(void) {
    return listOfKind(kNavbarStock, NSString.class);
}

void PGRSetNavbarStock(NSArray<NSString *> *stock) {
    [NSUserDefaults.standardUserDefaults setObject:stock ?: @[] forKey:kNavbarStock];
}

NSURL *PGRNavbarTabURL(NSString *uri) {
    NSURL *url = PGSpotifyURIFromText(uri);
    if ([url.absoluteString isEqualToString:@"spotify:collection:playlists"]) return [NSURL URLWithString:@"spotify:playlists"];
    return url;
}
