#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================================
// MARK: - Associated Keys & Constants
// ============================================================================

static const void *kSGAuditGlassTagKey = &kSGAuditGlassTagKey;
static const void *kSGCampfireInjectedKey = &kSGCampfireInjectedKey;
static const NSInteger kSGAuditGlassViewTag = 0x53474C53; // 'SGLS'
static const NSInteger kSGCampfireHeaderTag = 0x434D5046; // 'CMPF'

// ============================================================================
// MARK: - Liquid Glass Helper Engine (Matches Project Logic)
// ============================================================================

static BOOL SGIsDarkBackgroundColor(UIColor *color) {
    if (!color) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        if (a < 0.05) return NO;
        // Стандартные темные/серые фоны Spotify (#121212, #181818, #282828, #000000)
        CGFloat luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        return (luminance < 0.28 && a > 0.85);
    }
    return NO;
}

static UIVisualEffectView *SGCreateLiquidGlassView(CGRect bounds, CGFloat cornerRadius, BOOL isSheetOrPopup) {
    UIBlurEffectStyle style = isSheetOrPopup
        ? UIBlurEffectStyleSystemChromeMaterialDark
        : UIBlurEffectStyleSystemUltraThinMaterialDark;
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:style];
    UIVisualEffectView *glassView = [[UIVisualEffectView alloc] initWithEffect:blur];
    glassView.frame = bounds;
    glassView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glassView.userInteractionEnabled = NO;
    glassView.tag = kSGAuditGlassViewTag;

    if (cornerRadius > 0) {
        glassView.layer.cornerRadius = cornerRadius;
        glassView.layer.cornerCurve = kCACornerCurveContinuous;
        glassView.clipsToBounds = YES;
        // Тонкий блик Liquid Glass по периметру для шторок и тостов
        glassView.layer.borderWidth = 0.5;
        glassView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    }
    return glassView;
}

static void SGStripOpaqueBackgroundsRecursively(UIView *rootView, int depth, int maxDepth) {
    if (!rootView || depth > maxDepth) return;
    if (rootView.tag == kSGAuditGlassViewTag || [rootView isKindOfClass:[UIVisualEffectView class]]) {
        return;
    }

    if (SGIsDarkBackgroundColor(rootView.backgroundColor)) {
        rootView.backgroundColor = [UIColor clearColor];
    }

    if ([rootView isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)rootView;
        tv.backgroundColor = [UIColor clearColor];
        if (tv.backgroundView && ![tv.backgroundView isKindOfClass:[UIVisualEffectView class]]) {
            tv.backgroundView.backgroundColor = [UIColor clearColor];
        }
    } else if ([rootView isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)rootView;
        cv.backgroundColor = [UIColor clearColor];
        if (cv.backgroundView && ![cv.backgroundView isKindOfClass:[UIVisualEffectView class]]) {
            cv.backgroundView.backgroundColor = [UIColor clearColor];
        }
    }

    for (UIView *sub in rootView.subviews) {
        SGStripOpaqueBackgroundsRecursively(sub, depth + 1, maxDepth);
    }
}

static void SGDressViewWithGlass(UIView *view, CGFloat cornerRadius, BOOL isSheetOrPopup, int stripDepth) {
    if (!view) return;
    SGStripOpaqueBackgroundsRecursively(view, 0, stripDepth);

    UIVisualEffectView *existing = (UIVisualEffectView *)[view viewWithTag:kSGAuditGlassViewTag];
    if (!existing) {
        existing = SGCreateLiquidGlassView(view.bounds, cornerRadius, isSheetOrPopup);
        [view insertSubview:existing atIndex:0];
    } else {
        existing.frame = view.bounds;
        if (existing.superview == view && [view.subviews indexOfObject:existing] != 0) {
            [view sendSubviewToBack:existing];
        }
    }
}

// ============================================================================
// MARK: - 1. Campfire Force-Enable & SideDrawer Injection
// ============================================================================

// Помощник для открытия экрана Campfire (RecentChatsViewController или URI роутинг)
static void SGOpenCampfireFromController(UIViewController *sourceVC) {
    // 1. Пытаемся создать нативный RecentChatsViewController или ChatPageViewController, если он инициализируется
    NSArray<NSString *> *campfireClasses = @[
        @"_TtC27Campfire_RecentChatsPageImpl25RecentChatsViewController",
        @"Campfire_RecentChatsPageImpl.RecentChatsViewController",
        @"_TtC21Campfire_ChatPageImpl28ChatTabsContainerViewController",
        @"_TtC23Campfire_AddFriendsPageImpl24AddFriendsViewController"
    ];

    // 2. Сначала пробуем открыть через внутренний роутер Spotify по URI (самый надежный способ с DI)
    NSArray<NSString *> *uris = @[
        @"spotify:campfire",
        @"spotify:internal:campfire",
        @"spotify:chat",
        @"spotify:messages"
    ];
    for (NSString *uriStr in uris) {
        NSURL *url = [NSURL URLWithString:uriStr];
        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            return;
        }
    }

    // 3. Fallback: инстанцируем контроллер напрямую или показываем шторку Campfire
    for (NSString *clsName in campfireClasses) {
        Class cls = NSClassFromString(clsName);
        if (cls && [cls isSubclassOfClass:[UIViewController class]]) {
            @try {
                UIViewController *vc = [[cls alloc] init];
                if (vc) {
                    vc.modalPresentationStyle = UIModalPresentationPageSheet;
                    SGDressViewWithGlass(vc.view, 24.0, YES, 3);
                    [sourceVC presentViewController:vc animated:YES completion:nil];
                    return;
                }
            } @catch (__unused NSException *e) {}
        }
    }
}

// Добавление кнопки/секции Campfire в SideDrawer_ListPageImpl.ListViewController
static void SGInjectCampfireIntoSideDrawer(UIViewController *listVC) {
    if (!listVC || !listVC.isViewLoaded) return;
    UIView *rootView = listVC.view;

    // Проверяем, есть ли уже видимые сабвьюхи от Campfire
    for (UIView *sub in rootView.subviews) {
        NSString *clsName = NSStringFromClass([sub class]);
        if ([clsName containsString:@"Campfire"] || [clsName containsString:@"Chat"]) {
            sub.hidden = NO;
            sub.alpha = 1.0;
            return;
        }
    }

    // Ищем UITableView или UICollectionView или UIScrollView внутри ListViewController
    UIScrollView *targetScrollView = nil;
    for (UIView *sub in rootView.subviews) {
        if ([sub isKindOfClass:[UIScrollView class]]) {
            targetScrollView = (UIScrollView *)sub;
            break;
        }
        for (UIView *nested in sub.subviews) {
            if ([nested isKindOfClass:[UIScrollView class]]) {
                targetScrollView = (UIScrollView *)nested;
                break;
            }
        }
    }

    if ([rootView viewWithTag:kSGCampfireHeaderTag]) return;

    // Создаем стеклянную карточку-секцию Campfire в стиле Liquid Glass для бокового меню
    CGFloat width = rootView.bounds.size.width > 40 ? (rootView.bounds.size.width - 32.0) : 260.0;
    UIView *campfireBanner = [[UIView alloc] initWithFrame:CGRectMake(16.0, 0, width, 52.0)];
    campfireBanner.tag = kSGCampfireHeaderTag;
    campfireBanner.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIVisualEffectView *glass = SGCreateLiquidGlassView(campfireBanner.bounds, 14.0, YES);
    [campfireBanner addSubview:glass];

    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(14.0, 14.0, 24.0, 24.0)];
    if (@available(iOS 13.0, *)) {
        iconView.image = [UIImage systemImageNamed:@"bubble.left.and.bubble.right.fill"];
    }
    iconView.tintColor = [UIColor whiteColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [campfireBanner addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(50.0, 8.0, width - 90.0, 20.0)];
    titleLabel.text = @"Messages (Campfire)";
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor whiteColor];
    [campfireBanner addSubview:titleLabel];

    UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(50.0, 27.0, width - 90.0, 16.0)];
    subLabel.text = @"Share music & chat with friends";
    subLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    subLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    [campfireBanner addSubview:subLabel];

    UIImageView *chevron = [[UIImageView alloc] initWithFrame:CGRectMake(width - 28.0, 18.0, 12.0, 16.0)];
    if (@available(iOS 13.0, *)) {
        chevron.image = [UIImage systemImageNamed:@"chevron.right"];
    }
    chevron.tintColor = [UIColor colorWithWhite:1.0 alpha:0.45];
    chevron.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [campfireBanner addSubview:chevron];

    // Обработчик нажатия через блок/таргет
    UIButton *tapBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    tapBtn.frame = campfireBanner.bounds;
    tapBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    objc_setAssociatedObject(tapBtn, kSGCampfireInjectedKey, listVC, OBJC_ASSOCIATION_ASSIGN);
    [tapBtn addTarget:listVC action:NSSelectorFromString(@"sg_didTapCampfireEntry:") forControlEvents:UIControlEventTouchUpInside];
    [campfireBanner addSubview:tapBtn];

    if ([targetScrollView isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)targetScrollView;
        if (!tv.tableFooterView || tv.tableFooterView.bounds.size.height < 10) {
            UIView *footerWrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tv.bounds.size.width, 68.0)];
            campfireBanner.frame = CGRectMake(16.0, 8.0, tv.bounds.size.width - 32.0, 52.0);
            [footerWrap addSubview:campfireBanner];
            tv.tableFooterView = footerWrap;
            return;
        }
    }

    // Если там UICollectionView или кастомный стек — крепим в нижнюю часть SideDrawer над safeArea
    CGFloat yPos = rootView.bounds.size.height - rootView.safeAreaInsets.bottom - 68.0;
    campfireBanner.frame = CGRectMake(16.0, MAX(120.0, yPos), rootView.bounds.size.width - 32.0, 52.0);
    campfireBanner.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [rootView addSubview:campfireBanner];
}

// ============================================================================
// MARK: - 2. Master Class Lists from Static Audit (9.1.78)
// ============================================================================

// Категория А: Кастомные шторки (Bottom Sheets), попапы и их контейнеры
static NSArray<NSString *> *SGAuditPopupAndSheetControllerClasses(void) {
    static NSArray<NSString *> *classes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        classes = @[
            // Priority Music & Core Flows (popups_missing.txt Section A)
            @"_TtC29EncoreConsumerMobile_Wrappers25PopUpPresentableContainer",
            @"_TtC22Jam_MessagingSheetImpl28MessagingSheetViewController",
            @"_TtC32SongDNA_ContributorSheetPageImpl30ContributorSheetViewController",
            @"_TtC34AccountSwitching_AccountPickerImpl27AccountPickerViewController",
            @"_TtC35Settings_ConfirmationDialogPageImpl32ConfirmationDialogViewController",
            @"_TtC35Settings_ConfirmationDialogPageImpl36ConfirmationDialogPageViewController",
            @"_TtC51PlaylistCollaboration_PlaylistEditorsPickerPageImpl35PlaylistEditorsPickerViewController",
            @"_TtC28DevicePredictability_CoreKit25BottomSheetViewController",
            @"_TtC36DevicePredictability_WhereToPlayImpl25BottomSheetViewController",
            @"_TtC33MusicVideos_VideoConnectSheetImpl31VideoConnectSheetViewController",
            @"_TtC23NowPlaying_ElementsImpl38VideoSettingsBottomSheetViewController",
            @"_TtC23NowPlaying_ElementsImpl40VideoDisabledByPolicySheetViewController",
            @"_TtC28YourLibrary_YourLibraryXImpl25BottomSheetViewController",
            @"_TtC23Creator_CreatorPageImpl31ArtistBadgesSheetViewController",
            @"_TtC41Reporting_ReportActionContextMenuItemImpl31ReportSheetNavigationController",
            @"_TtC41Reporting_ReportActionContextMenuItemImpl25ReportSheetPageViewController",
            @"_TtC33Tome_MusicClientPageLoaderViewKit31DefaultErrorToastViewController",

            // Additional Bottom Sheets & Modals (popups_missing.txt Section B + ui_screens_to_check.txt)
            @"SPTLoginSlideUpModalViewController",
            @"SPTSortingFilteringPickerViewController",
            @"_TtC28Connect_DevicePickerPageImpl42DevicePickerBottomSheetContainerController",
            @"_TtC20Connect_VolumeUXImpl25BottomSheetViewController",
            @"_TtC36MusicPlaybackSpeed_SpeedControlBottomSheetImpl35SpeedControlBottomSheetViewController",
            @"_TtC20NavigationUI_InfoSheetImpl23InfoSheetViewController",
            @"_TtC30Artist_ArtistAttributionPageImpl38ArtistAttributionBottomSheetViewController",
            @"_TtC37Audiobook_ChaptersBottomSheetPageImpl33ChaptersBottomSheetViewController",
            @"_TtC45Audiobook_SupplementaryContentBottomSheetImpl45SupplementaryContentBottomSheetViewController",
            @"_TtC17DSA_MessagingImpl36DisableRecsBottomSheetViewController",
            @"_TtC20DSA_InlineToggleImpl47ConfirmRecommendationsBottomSheetViewController",
            @"_TtC19Marquee_MarqueeImpl32MarqueeContextMenuViewController",
            @"_TtC19Martini_ElementImpl29DisclaimerSheetViewController",
            @"_TtC19NowPlaying_ViewImpl36ActionShiftOverlayViewControllerImpl",
            @"_TtC28NowPlaying_ContentLayersImpl36HorizontalVideoOverlayViewController",
            @"_TtC35NowPlaying_ContentLayerPlatformImpl38VerticalFocusModeOverlayViewController",
            @"_TtC27Campfire_ChatDisclaimerImpl33ChatDisclaimerSheetViewController",
            @"_TtC21Campfire_ChatPageImpl29ChatPhotoPickerViewController",
            @"_TtC30Campfire_ChatGifPickerPageImpl27ChatGifPickerViewController",
            @"_TtC33Campfire_ChatEntityPickerPageImpl30ChatEntityPickerViewController",
            @"_TtC34Campfire_ChatContentPickerPageImpl31ChatContentPickerViewController",
            @"_TtC27GatedContent_MembershipsKit42PodcastMembershipBottomSheetViewController",
            @"_TtC44GatedContent_GatedContentBottomSheetPageImpl44GatedContentBottomSheetHostingViewController",
            @"_TtC27PodcastInteractivity_ECMKit33ModalReactionPickerViewController",
            @"_TtC33PodcastInteractivity_CommentsImpl27CommentsSheetViewController",
            @"_TtC33PodcastInteractivity_CommentsImpl27ReactionSheetViewController",
            @"_TtC39PodcastInteractivity_TermsSheetPageImpl24TermsSheetViewController",
            @"_TtC42PodcastInteractivity_ReactionSheetPageImpl31ReactionSheetPageViewController",
            @"_TtC28Contribution_ContextMenuImpl36ContributionInlineMenuViewController",
            @"_TtC28Contribution_ContextMenuImpl36ContributionNoteActionViewController",
            @"_TtC28Contribution_ContextMenuImpl40ContributionManageNoteMenuViewController",
            @"_TtC28Contribution_ContextMenuImpl42ContributionManageNotePickerViewController",
            @"_TtC28Contribution_ContextMenuImpl42ContributionReportNotePickerViewController",
            @"_TtC30Creator_AgentsPresentationImpl31AgentsBottomSheetViewController",
            @"_TtC30Reflection_SurveySheetPageImpl25SurveySheetViewController",
            @"_TtC32OnTour_MultiEventBottomSheetImpl31MultiEventBottomSheetController",
            @"_TtC38LiveEvents_MultiEventsBottomSheetPageImpl36MultiEventsBottomSheetViewController",
            @"_TtC26LiveEvents_FilterSheetImpl25FitlerSheetViewController",
            @"_TtC34Merchandising_BottomSheetDialogKit31BottomSheetDialogViewController",
            @"_TtC34Stickers_EnhancedShareCardPageImpl24FontPickerViewController",
            @"_TtC34Stickers_EnhancedShareCardPageImpl25ColorPickerViewController",
            @"_TtC34Stickers_EnhancedShareCardPageImpl25ImagePickerViewController",
            @"_TtC34Stickers_EnhancedShareCardPageImpl27StickerPickerViewController",
            @"_TtC34Transcript_TranscriptSelectionImpl30TranscriptPickerViewController",
            @"_TtC35AIPlaylist_PlaylistCreationPageImpl25BottomSheetViewController",
            @"_TtC35AllBoarding_AllBoardingPlatformImpl27ContentPickerViewController",
            @"_TtC36HighlightsStats_StatsDetailsPageImplP33_B1C2A05C4A2BFC9204FB50C482819D1C34ListenerSheetContentViewController",
            @"_TtC37Messaging_ClientMessagingPlatformImpl28ModalContainerViewController",
            @"_TtC37Messaging_ClientMessagingPlatformImpl52ClientMessagingPlatformBottomSheetPageViewController",
            @"_TtC41SocialInteractivity_ReactionSheetPageImpl27ReactionSheetViewController",
            @"_TtC41SocialListeningPartnerIntegrations_UIImpl32ConfirmationDialogViewController",
            @"_TtC45PartnerAccountLinking_AlexaAccountLinkingImpl43SPTAccountLinkingSlideUpModalViewController",
            @"_TtC46PlaylistCollaboration_PlaylistInviteDialogImpl32PlaylistInviteDialogViewController",
            @"_TtC33AlignedCuration_FirstSavePageImpl28FirstSaveSheetViewController"
        ];
    });
    return classes;
}

// Категория Б и Г: Полноэкранные и пуш-контроллеры из ui_screens_to_check.txt с [mentions 0]
static NSArray<NSString *> *SGAuditFullScreenControllerClasses(void) {
    static NSArray<NSString *> *classes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        classes = @[
            // Lyrics & Singalong
            @"_TtC30Lyrics_FullscreenSingalongPageImpl31FullscreenElementViewController",
            @"_TtC25Lyrics_LanguagePickerPageImpl37TranslationLanguagePickerViewController",
            @"_TtC17Lyrics_ReportPageImpl26LyricsReportViewController",
            @"_TtC20Lyrics_SelectionImpl26LyricsPickerViewController",

            // NowPlaying Settings & Overlays
            @"_TtC22NowPlaying_AgnosticModeImpl38AgnosticStickyHeaderContextRowViewController",
            @"_TtC30NowPlaying_ContextMenuSettingsImpl27AudioSettingsViewController",
            @"_TtC30NowPlaying_ContextMenuSettingsImpl27VideoSettingsViewController",
            @"_TtC23NowPlaying_ElementsImpl35VideoQualitySelectionViewController",
            @"_TtC28NowPlaying_VideoSettingsPageImpl31VideoSettingsPageHostViewController",
            @"_TtC27OnTour_OnTourNowPlayingViewImpl28OnTourNowPlayingViewController",

            // SongDNA
            @"_TtC19SongDNA_SongDNAPageImpl21SongDNAViewController",
            @"_TtC23SongDNA_UnavailablePageImpl25UnavailableViewController",

            // Campfire (All 14 submodules)
            @"_TtC23Campfire_AddFriendsPageImpl24AddFriendsViewController",
            @"_TtC27Campfire_RecentChatsPageImpl25RecentChatsViewController",
            @"_TtC21Campfire_ChatPageImpl22ChatPageViewController",
            @"_TtC21Campfire_ChatPageImpl28ChatTabsContainerViewController",
            @"_TtC21Campfire_ChatPageImpl26ChatInsightsViewController",
            @"_TtC21Campfire_ChatPageImpl24ChatSharesViewController",
            @"_TtC21Campfire_ChatPageImpl30ChatShareHistoryViewController",
            @"_TtC21Campfire_ChatPageImpl29ChatSettingsTabViewController",
            @"_TtC24Campfire_ChatDetailsPageImpl25ChatDetailsViewController",
            @"_TtC24Campfire_ChatDetailsPageImpl30EditGroupDetailsViewController",
            @"_TtC23Campfire_ChatMemberPageImpl24ChatMemberViewController",
            @"_TtC25Campfire_ChatSettingsPageImpl26ChatSettingsViewController",
            @"_TtC25Campfire_ChatSettingsPageImpl26ChatReceiptsViewController",
            @"_TtC28Campfire_ChatSharedMediaPageImpl29ChatSharedMediaViewController",
            @"_TtC20Campfire_ElementsKit26SharedByChatListViewController",
            @"_TtC18Campfire_SharePageImpl23ChatSharePageViewController",

            // Playlist Editing, Mixing, Collaboration, Creation
            @"_TtC34PlaylistEditing_PlaylistAnnotationImpl32PlaylistAnnotationViewController",
            @"_TtC35PlaylistEditing_PlaylistHistoryPageImpl33PlaylistHistoryPageViewController",
            @"_TtC35PlaylistEditing_PlaylistHistoryPageImpl36PlaylistHistoryPreviewViewController",
            @"_TtC34PlaylistMixing_LaterInPlaylistPageImpl29LaterInPlaylistViewController",
            @"_TtC40PlaylistMixing_MixingReorderOverviewPageImpl35MixingReorderOverviewViewController",
            @"_TtC46PlaylistCollaboration_PlaylistParticipantsImpl34PlaylistParticipantsViewController",
            @"_TtC35PlaylistCreation_CreatePlaylistImpl28CreatePlaylistViewController",

            // Creator & Artist Subpages
            @"_TtC21Creator_BiographyPageImpl23BiographyViewController",
            @"_TtC20Creator_ReleasesPageImpl22ReleasesViewController",
            @"_TtC23CollectionArtist_ArtistImpl28CollectionArtistViewController",
            @"_TtC23CollectionArtist_ArtistImpl34CollectionArtistHeaderViewController",

            // Settings, Account, Profile, Language
            @"_TtC19Settings_SearchPageImpl24SearchPageViewController",
            @"_TtC30AccountSwitching_AddAccountPageImpl24AddAccountViewController",
            @"_TtC47AccountSwitching_AddAccountTypeSelectionPageImpl37AddAccountTypeSelectionViewController",
            @"_TtC25Language_LanguageSettingsImpl30LanguageSettingsViewController",
            @"_TtC25Language_LanguageSettingsImpl35MusicLanguageSettingsViewController",
            @"_TtC22Profile_BlockedListImpl25BlockedListViewController",
            @"_TtC21Profile_CompletionImpl31ProfileCompletionViewController",
            @"_TtC18Profile_EditBioPageImpl21EditBioViewController",
            @"_TtC27Profile_EditSocialHandlePageImpl30EditSocialHandleViewController",
            @"_TtC22Profile_FriendsListPageImpl25FriendsListViewController",
            @"_TtC19Profile_PronounsPageImpl22PronounsViewController",
            @"_TtC29TasteProfile_TasteProfilePageImpl26TasteProfileViewController",

            // HighlightsStats (Listening Stats / Capsule)
            @"_TtC27HighlightsStats_SummaryPageImpl21SummaryViewController",
            @"_TtC32HighlightsStats_StatsDetailsPageImpl26StatsDetailsViewController",
            @"_TtC36HighlightsStats_HighlightDetailsPageImpl30HighlightDetailsViewController",
            @"_TtC28HighlightsStats_UserTimelineImpl26UserTimelineViewController",

            // Blend, Jam, ListeningActivity, ListeningParties
            @"_TtC17Blend_BlendEntityImpl16BEEditViewController",
            @"_TtC17Blend_BlendEntityImpl21MembersViewController",
            @"_TtC21Blend_BlendInvitationImpl16BIViewController",
            @"_TtC12Jam_UIImpl32OnboardingSlateV2ViewControllerImpl",
            @"_TtC49ListeningActivity_ListeningActivityDetailsPageImpl38ListeningActivityDetailsViewController",
            @"_TtC40ListeningActivity_AudienceSettingPageImpl29AudienceSettingViewController",
            @"_TtC31ListeningParties_LivestreamPageImpl28LivestreamPageViewController",

            // Browse, Radio, Upcoming, LiveEvents, WatchFeed
            @"_TtC16Browse_GenrePageImpl23GenrePageViewController",
            @"_TtC15Radio_RadioPageImpl22RadioHubViewController",
            @"_TtC22Upcoming_ReleasesHubPageImpl25ReleasesHubViewController",
            @"_TtC25LiveEvents_LiveEventsPageImpl28LiveEventsPageViewController",
            @"_TtC24LiveEvents_LiveEventPageImpl23LiveEventViewController",
            @"_TtC28WatchFeed_WatchFeedFeatureImpl31WatchFeedFeatureViewController",
            @"_TtC20WatchFeed_PivotsPageImpl20PivotsViewController",

            // Share Formats & Stickers
            @"_TtC12Share_LyricsImpl29LyricsShareFormatViewController",
            @"_TtC18Share_ShareFormatsImpl30DefaultShareFormatViewController",
            @"_TtC17Share_TranscriptsImpl34TranscriptsShareFormatViewController",
            @"_TtC34Stickers_EnhancedShareCardPageImpl31EnhancedShareCardViewController",
            @"_TtC27Stickers_LyricsStickersPageImpl28LyricsStickersViewController",

            // LimitedExperienceIndicator
            @"_TtC43LimitedExperienceIndicator_MessageBarRuntime24MessageBarViewController"
        ];
    });
    return classes;
}

// Категория В: Кастомные UIView шторок, тостов и снэкбаров
static NSArray<NSString *> *SGAuditToastAndSheetViewClasses(void) {
    static NSArray<NSString *> *classes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        classes = @[
            @"SPTSnackbarCurationView",
            @"SPTSnackbarAnimationView",
            @"_TtC16Login_LoginUIKit12SnackbarView",
            @"_TtC21Martini_AgentPageImpl18InlineSnackbarView",
            @"_TtC24Martini_FloatingChatImpl24FloatingChatSnackbarView",
            @"_TtC33Tome_MusicClientPageLoaderViewKit21DefaultErrorToastView",
            @"_TtC20Connect_VolumeUXImpl15BottomSheetView",
            @"_TtC20Lyrics_SelectionImpl16LyricsPickerView",
            @"_TtC27Campfire_ChatDisclaimerImpl23ChatDisclaimerSheetView",
            @"_TtC30Creator_AgentsPresentationImpl21AgentsBottomSheetView",
            @"_TtC30PlaylistCreation_SheetPageImpl25BICreatePlaylistSheetView",
            @"_TtC33AlignedCuration_FirstSavePageImpl18FirstSaveSheetView",
            @"_TtC33MusicVideos_VideoConnectSheetImpl21VideoConnectSheetView",
            @"_TtC34Merchandising_BottomSheetDialogKit21BottomSheetDialogView",
            @"_TtC34Transcript_TranscriptSelectionImpl20TranscriptPickerView",
            @"_TtC46PlaylistCollaboration_PlaylistInviteDialogImpl24PlaylistInviteDialogView"
        ];
    });
    return classes;
}

// ============================================================================
// MARK: - 3. Dynamic Runtime Swizzling & Hook Installation
// ============================================================================

static void SGSwizzleMethod(Class cls, SEL sel, IMP newImp, IMP *origImpOut, const char *types) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        if (origImpOut) *origImpOut = method_getImplementation(m);
        if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(m))) {
            method_setImplementation(m, newImp);
        }
    } else if (types) {
        class_addMethod(cls, sel, newImp, types);
    }
}

static void SGHookControllerClassForGlass(NSString *className, BOOL isSheetOrPopup) {
    Class cls = NSClassFromString(className);
    if (!cls) return;

    SEL selLayout = @selector(viewDidLayoutSubviews);
    Method m = class_getInstanceMethod(cls, selLayout);
    IMP origImp = m ? method_getImplementation(m) : NULL;

    IMP newImp = imp_implementationWithBlock(^(UIViewController *self) {
        if (origImp) {
            ((void (*)(id, SEL))origImp)(self, selLayout);
        }
        if (self.isViewLoaded && self.view) {
            CGFloat radius = isSheetOrPopup ? 24.0 : 0.0;
            int depth = isSheetOrPopup ? 4 : 2;
            SGDressViewWithGlass(self.view, radius, isSheetOrPopup, depth);
        }
    });

    SGSwizzleMethod(cls, selLayout, newImp, NULL, "v@:");
}

static void SGHookViewClassForGlass(NSString *className, CGFloat cornerRadius) {
    Class cls = NSClassFromString(className);
    if (!cls) return;

    SEL selLayout = @selector(layoutSubviews);
    Method m = class_getInstanceMethod(cls, selLayout);
    IMP origImp = m ? method_getImplementation(m) : NULL;

    IMP newImp = imp_implementationWithBlock(^(UIView *self) {
        if (origImp) {
            ((void (*)(id, SEL))origImp)(self, selLayout);
        }
        SGDressViewWithGlass(self, cornerRadius, YES, 3);
    });

    SGSwizzleMethod(cls, selLayout, newImp, NULL, "v@:");
}

static void SGHookPresentationControllerClass(NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return;

    SEL selLayout = @selector(containerViewWillLayoutSubviews);
    Method m = class_getInstanceMethod(cls, selLayout);
    IMP origImp = m ? method_getImplementation(m) : NULL;

    IMP newImp = imp_implementationWithBlock(^(UIPresentationController *self) {
