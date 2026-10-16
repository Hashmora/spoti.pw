// Redesign: glass for more of Spotify's bottom sheets, each hosted by its own controller in the same Navigation sheet
// (id=sheet-view, #1F1F1F) the queue, the sleep timer and the Connect picker are, and none of them given a pane yet:
// the playback speed, audio and video settings, chapters (episodes and audiobooks), the lyrics picker and its
// translation language, the report sheet, the info sheet, the first-save sheet, snooze, mark as played, the
// playlist invite, the audio language and subtitles pickers.
//
// Picked from the class dump of 9.1.78, not from a screen of yours: SGRGlassSheetChrome does nothing for a
// controller whose view is not inside a "sheet-view" (it returns at once), so one of these that Spotify presents some
// other way is left as it was. Open each sheet with the PaintAudit report on (three-finger press) and delete the
// block of a sheet that already looks right or that the audit shows as presented outside Navigation's sheet.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static void chrome(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (root) SGRGlassSheetChrome(root);
}


%hook _TtC46MusicPlaybackSpeed_SpeedControlBottomSheetImpl37SpeedControlBottomSheetViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC34NowPlaying_ContextMenuSettingsImpl27AudioSettingsViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC34NowPlaying_ContextMenuSettingsImpl27VideoSettingsViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC32EpisodeChapters_ChaptersListImpl30ChaptersListViewControllerImpl
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC37Audiobook_ChaptersBottomSheetPageImpl33ChaptersBottomSheetViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC20Lyrics_SelectionImpl26LyricsPickerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC29Lyrics_LanguagePickerPageImpl39TranslationLanguagePickerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC41Reporting_ReportActionContextMenuItemImpl29ReportSheetPageViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC26NavigationUI_InfoSheetImpl23InfoSheetViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC33AlignedCuration_FirstSavePageImpl28FirstSaveSheetViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC39Collection_SnoozeRecommendationPageImpl34SnoozeRecommendationViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC29MarkAsPlayed_MarkAsPlayedImpl26MarkAsPlayedViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC46PlaylistCollaboration_PlaylistInviteDialogImpl34PlaylistInviteDialogViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC33Betamax_AudioLanguageSelectorImpl35AudioLanguageSelectorViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%hook _TtC21Betamax_SubtitlesImpl32SubtitlesSelectionViewController
- (void)viewDidLayoutSubviews {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    chrome((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController *weak = (UIViewController *)self;
    chrome((UIViewController *)self);
    // Spotify paints the grey back on later passes; the rows are built after the first layout.
    for (NSNumber *delay in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) chrome(weak);
        });
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC46MusicPlaybackSpeed_SpeedControlBottomSheetImpl37SpeedControlBottomSheetViewController",
        @"_TtC34NowPlaying_ContextMenuSettingsImpl27AudioSettingsViewController",
        @"_TtC34NowPlaying_ContextMenuSettingsImpl27VideoSettingsViewController",
        @"_TtC32EpisodeChapters_ChaptersListImpl30ChaptersListViewControllerImpl",
        @"_TtC37Audiobook_ChaptersBottomSheetPageImpl33ChaptersBottomSheetViewController",
        @"_TtC20Lyrics_SelectionImpl26LyricsPickerViewController",
        @"_TtC29Lyrics_LanguagePickerPageImpl39TranslationLanguagePickerViewController",
        @"_TtC41Reporting_ReportActionContextMenuItemImpl29ReportSheetPageViewController",
        @"_TtC26NavigationUI_InfoSheetImpl23InfoSheetViewController",
        @"_TtC33AlignedCuration_FirstSavePageImpl28FirstSaveSheetViewController",
        @"_TtC39Collection_SnoozeRecommendationPageImpl34SnoozeRecommendationViewController",
        @"_TtC29MarkAsPlayed_MarkAsPlayedImpl26MarkAsPlayedViewController",
        @"_TtC46PlaylistCollaboration_PlaylistInviteDialogImpl34PlaylistInviteDialogViewController",
        @"_TtC33Betamax_AudioLanguageSelectorImpl35AudioLanguageSelectorViewController",
        @"_TtC21Betamax_SubtitlesImpl32SubtitlesSelectionViewController"
    ]);
}
