// The Profile redesign, iOS < 26: the lists a person's profile opens (Followers, Following, the playlists they
// have), pages holding Profile_CommonImpl.ProfileListView under UIKit's own navigation bar.
//
//     ProfileListBar.x  the bar the way the playlist's has it (Pages/PageBar.m): the back button on a glass
//                       circle pinned to the corner, the title on a glass capsule, the dark blur Spotify lays
//                       behind the bar gone
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI), and below iOS 26: from 26 on UIKit's own
// bar is glass already.
// Threading: main thread only.
