//
//  MyConfiguration.swift
//  Easydict
//
//  Created by ljk on 2024/1/2.
//  Copyright © 2024 izual. All rights reserved.
//

import Combine
import Defaults
import Foundation

// MARK: - LanguageDetectOptimize

@objc
enum LanguageDetectOptimize: Int {
    case none = 0
    case baidu = 1
    case google = 2
}

// MARK: - EnglishPronunciation

@objc
enum EnglishPronunciation: Int {
    case uk = 1
    case us
}

// MARK: - MyConfiguration

/// Singleton class to manage application configuration settings.
/// This class uses the `Defaults` library to persist settings and provides
/// reactive updates using Combine.
@objcMembers
class MyConfiguration: NSObject {
    // MARK: Lifecycle

    override private init() {
        super.init()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            observeKeys()
        }
    }

    // MARK: Internal

    private(set) static var shared = MyConfiguration()

    @DefaultsWrapper(.firstLanguage) var firstLanguage: Language
    @DefaultsWrapper(.secondLanguage) var secondLanguage: Language
    @DefaultsWrapper(.queryFromLanguage) var fromLanguage: Language
    @DefaultsWrapper(.queryToLanguage) var toLanguage: Language
    @DefaultsWrapper(.languageDetectOptimize) var languageDetectOptimize: LanguageDetectOptimize

    @DefaultsWrapper(.autoShowQueryIcon) var autoSelectText: Bool
    @DefaultsWrapper(.autoShowQueryIconExcludedLanguage) var autoShowQueryIconExcludedLanguage: Language
    @DefaultsWrapper(.autoShowQueryIconMinTextLength) var autoShowQueryIconMinTextLength: Int
    @DefaultsWrapper(.enableForceGetSelectedText) var enableForceGetSelectedText: Bool
    @DefaultsWrapper(.clickQuery) var clickQuery: Bool

    @DefaultsWrapper(.mouseSelectTranslateWindowType) var mouseSelectTranslateWindowType:
        EZWindowType
    @DefaultsWrapper(.shortcutSelectTranslateWindowType) var shortcutSelectTranslateWindowType:
        EZWindowType
    @DefaultsWrapper(.fixedWindowPosition) var fixedWindowPosition: EZShowWindowPosition
    @DefaultsWrapper(.miniWindowPosition) var miniWindowPosition: EZShowWindowPosition
    @DefaultsWrapper(.pinWindowWhenDisplayed) var pinWindowWhenDisplayed
    @DefaultsWrapper(.hideMainWindow) var hideMainWindow: Bool

    @DefaultsWrapper(.clearQueryWhenInputTranslate) var clearInput: Bool
    @DefaultsWrapper(.keepPrevResultWhenSelectTranslateTextIsEmpty) var keepPrevResultWhenEmpty:
        Bool
    @DefaultsWrapper(.selectQueryTextWhenWindowActivate) var selectQueryTextWhenWindowActivate: Bool
    @DefaultsWrapper(.automaticallyRemoveCodeCommentSymbols) var automaticallyRemoveCodeCommentSymbols: Bool
    @DefaultsWrapper(.automaticWordSegmentation) var automaticWordSegmentation: Bool
    @DefaultsWrapper(.replaceNewlineWithSpace) var replaceNewlineWithSpace: Bool
    @DefaultsWrapper(.enableRemoveBooksExcerptInfo) var enableRemoveBooksExcerptInfo: Bool

    @DefaultsWrapper(.autoQueryOCRText) var autoQueryOCRText: Bool
    @DefaultsWrapper(.autoQuerySelectedText) var autoQuerySelectedText: Bool
    @DefaultsWrapper(.autoQueryPastedText) var autoQueryPastedText: Bool
    @DefaultsWrapper(.autoQueryWhenTextChanged) var autoQueryWhenTextChanged: Bool
    @DefaultsWrapper(.autoPlayAudio) var autoPlayAudio: Bool
    @DefaultsWrapper(.pronunciation) var pronunciation: EnglishPronunciation
    @DefaultsWrapper(.preferYoudaoTTSForEnglishWord) var preferYoudaoTTSForEnglishWord: Bool

    @DefaultsWrapper(.autoCopySelectedText) var autoCopySelectedText: Bool
    @DefaultsWrapper(.autoCopyOCRText) var autoCopyOCRText: Bool
    @DefaultsWrapper(.autoCopyFirstTranslatedText) var autoCopyFirstTranslatedText: Bool

    @DefaultsWrapper(.showGoogleQuickLink) var showGoogleQuickLink: Bool
    @DefaultsWrapper(.showEudicQuickLink) var showEudicQuickLink: Bool
    @DefaultsWrapper(.showAppleDictionaryQuickLink) var showAppleDictionaryQuickLink: Bool
    @DefaultsWrapper(.showQuickActionButton) var showQuickActionButton: Bool

    @DefaultsWrapper(.appearanceType) var appearance: AppearanceType
    @DefaultsWrapper(.hideMenuBarIcon) var hideMenuBarIcon: Bool
    @DefaultsWrapper(.fontSizeOptionIndex) var fontSizeIndex: UInt
    @DefaultsWrapper(.enableMarkdownRendering) var enableMarkdownRendering: Bool

    // Advanced Tab
    @DefaultsWrapper(.enableBetaFeature) private(set) var beta: Bool
    @DefaultsWrapper(.enableYoudaoOCR) var enableYoudaoOCR: Bool
    @DefaultsWrapper(.enableCompatibilityReplace) var enableCompatibilityReplace: Bool
    @DefaultsWrapper(.forceGetSelectedTextType) var forceGetSelectedTextType:
        ForceGetSelectedTextType

    @DefaultsWrapper(.enableAppleOfflineTranslation) var enableAppleOfflineTranslation: Bool
    @DefaultsWrapper(.enableOCRTextNormalization) var enableOCRTextNormalization: Bool
    @DefaultsWrapper(.isScreenshotTipLayerHidden) var isScreenshotTipLayerHidden: Bool
    @DefaultsWrapper(.formerFixedScreenVisibleFrame) var formerFixedScreenVisibleFrame: CGRect
    @DefaultsWrapper(.formerMiniScreenVisibleFrame) var formerMiniScreenVisibleFrame: CGRect
    @DefaultsWrapper(.enableAnkiConnect) var enableAnkiConnect: Bool

    @DefaultsWrapper(.preferAppleScriptAPI) var preferAppleScriptAPI: Bool

    // Max window height percentage, e.g., 80 means 80% of the screen height
    @DefaultsWrapper(.maxWindowHeightPercentage) var maxWindowHeightPercentage: Int

    @ShortcutWrapper(.pinShortcut) var pinShortcutString: String
    @ShortcutWrapper(.googleShortcut) var googleShortcutString: String
    @ShortcutWrapper(.appleDictionaryShortcut) var appleDictShortcutString: String
    @ShortcutWrapper(.eudicShortcut) var eudicDictShortcutString: String

    let updater = GlobalContext.shared.updaterController.updater
    let fontSizes: [CGFloat] = [1, 1.1, 1.2, 1.3, 1.4]
    var disabledAutoSelect: Bool = false
    var isRecordingSelectTextShortcutKey: Bool = false
    var cancellables: Set<AnyCancellable> = []

    var fontSizeRatio: CGFloat {
        let safeIndex = max(0, min(Int(fontSizeIndex), fontSizes.count - 1))
        return fontSizes[safeIndex]
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            updater.automaticallyChecksForUpdates
        }
        set {
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    var defaultTTSServiceType: ServiceType {
        get {
            ServiceType(rawValue: Defaults[.defaultTTSServiceType].rawValue)
        }
        set {
            Defaults[.defaultTTSServiceType] =
                TTSServiceType(rawValue: newValue.rawValue) ?? .youdao
        }
    }

    static func destroySharedInstance() {
        shared = MyConfiguration()
    }

    func enableBetaFeaturesIfNeeded() {
        guard beta else { return }
    }

    // MARK: Private

    private func observeKeys() {
        Defaults.publisher(.autoShowQueryIcon, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.didSetAutoSelectText()
            }
            .store(in: &cancellables)

        Defaults.publisher(.clickQuery, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.didSetClickQuery()
            }
            .store(in: &cancellables)

        Defaults.publisher(.hideMainWindow, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.didSetHideMainWindow()
            }
            .store(in: &cancellables)

        Defaults.publisher(.showGoogleQuickLink, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.didSetShowGoogleQuickLink()
            }
            .store(in: &cancellables)

        Defaults.publisher(.showEudicQuickLink, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.didSetShowEudicQuickLink()
            }
            .store(in: &cancellables)

        Defaults.publisher(.showAppleDictionaryQuickLink, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.didSetShowAppleDictionaryQuickLink()
            }
            .store(in: &cancellables)

        Defaults.publisher(.showQuickActionButton, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.didSetShowSettingQuickLink()
            }
            .store(in: &cancellables)

        Defaults.publisher(.fontSizeOptionIndex, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.didSetFontSizeIndex()
            }
            .store(in: &cancellables)

        Defaults.publisher(.appearanceType, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                let newValue = change.newValue
                self?.didSetAppearance(newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(
            keys: [
                .pinShortcut,
                .appleDictionaryShortcut,
                .googleShortcut,
                .eudicShortcut,
            ],
            options: []
        )
        .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
        .receive(on: DispatchQueue.main)
        .sink { _ in
            EZWindowManager.shared().updateWindowsTitlebarButtonsToolTip()
        }
        .store(in: &cancellables)

        Defaults.publisher(.enableHTTPServer)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { change in
                let isOn = change.newValue
                Task {
                    await VaporServer.shared.startServer(isOn: isOn)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: setter

extension MyConfiguration {
    fileprivate func didSetAutoSelectText() {
        EventMonitor.shared.addBothMonitor(autoSelectText)
    }

    fileprivate func didSetClickQuery() {
        EZWindowManager.shared().updatePopButtonQueryAction()
    }

    fileprivate func didSetHideMainWindow() {
        let windowManger = EZWindowManager.shared()
        windowManger.updatePopButtonQueryAction()
        if hideMainWindow {
            windowManger.destroyMainWindow()
        }
    }

    fileprivate func didSetShowGoogleQuickLink() {
        postUpdateQuickLinkButtonNotification()
    }

    fileprivate func didSetShowEudicQuickLink() {
        postUpdateQuickLinkButtonNotification()
    }

    fileprivate func didSetShowAppleDictionaryQuickLink() {
        postUpdateQuickLinkButtonNotification()
    }

    func didSetShowSettingQuickLink() {
        postUpdateQuickLinkButtonNotification()
    }

    fileprivate func didSetFontSizeIndex() {
        NotificationCenter.default.post(name: .didChangeFontSize, object: nil)
    }

    fileprivate func didSetAppearance(_ appearance: AppearanceType) {
        DarkModeManager.shared.updateDarkMode(appearance)
    }
}

extension MyConfiguration {
    fileprivate func postUpdateQuickLinkButtonNotification() {
        let notification = Notification(name: Notification.Name.linkButtonUpdated, object: nil)
        NotificationCenter.default.post(notification)
    }
}
