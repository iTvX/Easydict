//
//  ShortcutManager+Default.swift
//  Easydict
//
//  Created by Sharker on 2024/2/5.
//  Copyright © 2024 izual. All rights reserved.
//

import Defaults
import Magnet

// MARK: - ShortcutManager + Defaults Settings

extension ShortcutManager {
    // Set default hotkeys: only select-translate and the mini window; every other shortcut starts empty
    func setDefaultShortcutKeys() {
        Defaults[.selectionShortcut] = KeyCombo(key: .d, cocoaModifiers: .option)
        Defaults[.showMiniWindowShortcut] = KeyCombo(key: .f, cocoaModifiers: .option)
    }
}

// MARK: - ShortcutManager + GlobalShortcut

extension ShortcutManager {
    /// Setup global shortcut actions
    func setupGlobalShortcutActions() {
        for action in ShortcutAction.globalActions {
            if let key = action.defaultsKey {
                let keyCombo = Defaults[key]
                bindingGlobalShortcutAction(keyCombo: keyCombo, action: action)
            }
        }
    }

    /// Bind global shortcut action (registers as system-wide hotkey)
    func bindingGlobalShortcutAction(keyCombo: KeyCombo?, action: ShortcutAction) {
        HotKeyCenter.shared.unregisterHotKey(with: action.rawValue)

        // Ensure the action is a global action and keyCombo is valid
        guard let keyCombo, action.isGlobal else {
            return
        }

        let hotKey = HotKey(
            identifier: action.rawValue,
            keyCombo: keyCombo
        ) { _ in
            Task { @MainActor in
                action.executeAction()
            }
        }

        hotKey.register()
    }
}
