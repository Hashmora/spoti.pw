#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGSection(@"Header", @[
            SGOptionRow(@"Artwork background", nil, SGKeyAlbumBackdrop),
            // Spotify's own: a tap on the cover opens it full screen, where it turns a little with the phone.
            SGKillRow(@"No tilting full screen cover", @"ios-creativeworkcommons-cover-art-tilt-configuration-kit.cover_art_tilt_enabled"),
        ]),
        SGSection(@"Hide in the header", @[
            SGHideRow(@"Explore (video deck)", nil, SGHideAlbumExplore),
            SGHideRow(@"Add to library", nil, SGHideAlbumAddTo),
            SGHideRow(@"Download", nil, SGHideAlbumDownload),
            SGHideRow(@"More options", nil, SGHideAlbumMore),
        ]),
        SGNotedSection(@"Hide on the page", @[
            SGHideRow(@"More by the artist", nil, SGHideAlbumMoreBy),
            SGHideRow(@"Related music videos", nil, SGHideAlbumVideos),
            SGHideRow(@"Concerts", nil, SGHideAlbumConcerts),
            SGHideRow(@"Merch", nil, SGHideAlbumMerch),
            SGHideRow(@"You might also like", nil, SGHideAlbumYouMightLike),
        ], @"Works only with Spotify in English."),
    ];
    return [[SGModPage alloc] initWithTitle:@"Album" intro:nil sections:sections footer:nil];
}
