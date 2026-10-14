// The Profile redesign, iOS < 26: the lists a person's profile opens (Followers, Following, the playlists they
// have), pages of Profile_CommonImpl.ProfileListViewController under UIKit's own navigation bar.
//
//     ProfileListBar.x  the bar the way the playlist's has it: the back button on glass, the title on a glass
//                       capsule, and the dark blur Spotify lays behind the bar gone
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI), and below iOS 26: from 26 on UIKit's own
// bar is glass already.
// Threading: main thread only.
