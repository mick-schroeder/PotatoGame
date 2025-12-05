// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import Observation
import SwiftUI

#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

// MARK: - Actions

enum GameInputAction: String, CaseIterable, Identifiable, Codable {
    case nextCluster
    case confirmCluster
    case clearSelection

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .nextCluster:
            LocalizedStringResource("Next Match Cluster")
        case .confirmCluster:
            LocalizedStringResource("Confirm Selection")
        case .clearSelection:
            LocalizedStringResource("Clear Selection")
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .nextCluster:
            LocalizedStringResource("Cycles focus through available matches.")
        case .confirmCluster:
            LocalizedStringResource("Collects the highlighted cluster.")
        case .clearSelection:
            LocalizedStringResource("Cancels the current selection.")
        }
    }

    var defaultShortcuts: [GameKeyShortcut] {
        switch self {
        case .nextCluster:
            [.tab]
        case .confirmCluster:
            [.space, .returnKey]
        case .clearSelection:
            [.escape]
        }
    }
}

enum GameDirectionCommand: String, CaseIterable, Identifiable, Codable {
    case moveUp
    case moveDown
    case moveLeft
    case moveRight

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .moveUp:
            LocalizedStringResource("Tilt Up")
        case .moveDown:
            LocalizedStringResource("Tilt Down")
        case .moveLeft:
            LocalizedStringResource("Tilt Left")
        case .moveRight:
            LocalizedStringResource("Tilt Right")
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .moveUp:
            LocalizedStringResource("Applies upward gravity while held.")
        case .moveDown:
            LocalizedStringResource("Applies downward gravity while held.")
        case .moveLeft:
            LocalizedStringResource("Applies left gravity while held.")
        case .moveRight:
            LocalizedStringResource("Applies right gravity while held.")
        }
    }

    var defaultShortcuts: [GameKeyShortcut] {
        switch self {
        case .moveUp:
            [.arrowUp, GameKeyShortcut(characters: "w")]
        case .moveDown:
            [.arrowDown, GameKeyShortcut(characters: "s")]
        case .moveLeft:
            [.arrowLeft, GameKeyShortcut(characters: "a")]
        case .moveRight:
            [.arrowRight, GameKeyShortcut(characters: "d")]
        }
    }
}

private enum GameKeyCharacters {
    static let tab = "\t"
    static let space = " "
    static let escape = "\u{1b}"
    static let carriageReturn = "\r"
    static let delete = "\u{8}"
    static let arrowUp = "\u{F700}"
    static let arrowDown = "\u{F701}"
    static let arrowLeft = "\u{F702}"
    static let arrowRight = "\u{F703}"
}

// MARK: - Modifiers

struct GameKeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt8

    static let command = GameKeyModifiers(rawValue: 1 << 0)
    static let option = GameKeyModifiers(rawValue: 1 << 1)
    static let control = GameKeyModifiers(rawValue: 1 << 2)
    static let shift = GameKeyModifiers(rawValue: 1 << 3)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    #if os(macOS)
        init(eventFlags: NSEvent.ModifierFlags) {
            var value: GameKeyModifiers = []
            if eventFlags.contains(.command) { value.insert(.command) }
            if eventFlags.contains(.option) { value.insert(.option) }
            if eventFlags.contains(.control) { value.insert(.control) }
            if eventFlags.contains(.shift) { value.insert(.shift) }
            self = value
        }
    #endif

    #if os(iOS)
        init(uiFlags: UIKeyModifierFlags) {
            var value: GameKeyModifiers = []
            if uiFlags.contains(.command) { value.insert(.command) }
            if uiFlags.contains(.alternate) { value.insert(.option) }
            if uiFlags.contains(.control) { value.insert(.control) }
            if uiFlags.contains(.shift) { value.insert(.shift) }
            self = value
        }
    #endif

    var symbols: String {
        var output = ""
        if contains(.control) { output.append("⌃") }
        if contains(.option) { output.append("⌥") }
        if contains(.shift) { output.append("⇧") }
        if contains(.command) { output.append("⌘") }
        return output
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if contains(.command) { modifiers.insert(.command) }
        if contains(.option) { modifiers.insert(.option) }
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    #if os(iOS)
        var uiKeyModifiers: UIKeyModifierFlags {
            var modifiers: UIKeyModifierFlags = []
            if contains(.command) { modifiers.insert(.command) }
            if contains(.option) { modifiers.insert(.alternate) }
            if contains(.shift) { modifiers.insert(.shift) }
            if contains(.control) { modifiers.insert(.control) }
            return modifiers
        }
    #endif

    #if os(macOS)
        var nsEventFlags: NSEvent.ModifierFlags {
            var modifiers: NSEvent.ModifierFlags = []
            if contains(.command) { modifiers.insert(.command) }
            if contains(.option) { modifiers.insert(.option) }
            if contains(.shift) { modifiers.insert(.shift) }
            if contains(.control) { modifiers.insert(.control) }
            return modifiers
        }
    #endif
}

// MARK: - Shortcut

struct GameKeyShortcut: Codable, Hashable {
    var characters: String
    var modifiers: GameKeyModifiers
    var macKeyCode: UInt16?
    var hidUsage: UInt16?

    init(characters: String, modifiers: GameKeyModifiers = [], macKeyCode: UInt16? = nil, hidUsage: UInt16? = nil) {
        self.characters = characters
        self.modifiers = modifiers
        self.macKeyCode = macKeyCode
        self.hidUsage = hidUsage
    }

    var normalizedCharacters: String {
        String(characters.lowercased().prefix(1))
    }

    var displayLabel: String {
        let keyLabel = Self.displayName(for: normalizedCharacters)
        let modifierSymbols = modifiers.symbols
        return modifierSymbols + keyLabel
    }

    func keyboardShortcut() -> KeyboardShortcut? {
        guard let keyEquivalent else { return nil }
        return KeyboardShortcut(keyEquivalent, modifiers: modifiers.eventModifiers)
    }

    private var keyEquivalent: KeyEquivalent? {
        switch normalizedCharacters {
        case "\t":
            return .tab
        case " ":
            return .space
        case "\u{1b}":
            return .escape
        case "\r":
            return .return
        case "\u{8}":
            return .delete
        default:
            guard let scalar = normalizedCharacters.first else { return nil }
            return KeyEquivalent(scalar)
        }
    }

    private static func displayName(for value: String) -> String {
        switch value {
        case GameKeyCharacters.tab:
            "⇥"
        case GameKeyCharacters.space:
            "Space"
        case GameKeyCharacters.escape:
            "⎋"
        case GameKeyCharacters.carriageReturn:
            "↩︎"
        case GameKeyCharacters.delete:
            "⌫"
        case GameKeyCharacters.arrowUp:
            "↑"
        case GameKeyCharacters.arrowDown:
            "↓"
        case GameKeyCharacters.arrowLeft:
            "←"
        case GameKeyCharacters.arrowRight:
            "→"
        default:
            value.uppercased()
        }
    }
}

extension GameKeyShortcut {
    static let tab = GameKeyShortcut(characters: GameKeyCharacters.tab, macKeyCode: 48,
                                     hidUsage: defaultUsage(for: .keyboardTab))
    static let space = GameKeyShortcut(characters: GameKeyCharacters.space, macKeyCode: 49,
                                       hidUsage: defaultUsage(for: .keyboardSpacebar))
    static let returnKey = GameKeyShortcut(characters: GameKeyCharacters.carriageReturn, macKeyCode: 36,
                                           hidUsage: defaultUsage(for: .keyboardReturnOrEnter))
    static let escape = GameKeyShortcut(characters: GameKeyCharacters.escape, macKeyCode: 53,
                                        hidUsage: defaultUsage(for: .keyboardEscape))
    static let arrowUp = GameKeyShortcut(characters: GameKeyCharacters.arrowUp, macKeyCode: 126,
                                         hidUsage: defaultUsage(for: .keyboardUpArrow))
    static let arrowDown = GameKeyShortcut(characters: GameKeyCharacters.arrowDown, macKeyCode: 125,
                                           hidUsage: defaultUsage(for: .keyboardDownArrow))
    static let arrowLeft = GameKeyShortcut(characters: GameKeyCharacters.arrowLeft, macKeyCode: 123,
                                           hidUsage: defaultUsage(for: .keyboardLeftArrow))
    static let arrowRight = GameKeyShortcut(characters: GameKeyCharacters.arrowRight, macKeyCode: 124,
                                            hidUsage: defaultUsage(for: .keyboardRightArrow))

    private enum Usage {
        case keyboardTab
        case keyboardSpacebar
        case keyboardReturnOrEnter
        case keyboardEscape
        case keyboardUpArrow
        case keyboardDownArrow
        case keyboardLeftArrow
        case keyboardRightArrow
    }

    private static func defaultUsage(for usage: Usage) -> UInt16? {
        #if os(iOS)
            if #available(iOS 13.4, *) {
                switch usage {
                case .keyboardTab:
                    return usageValue(UIKeyboardHIDUsage.keyboardTab)
                case .keyboardSpacebar:
                    return usageValue(UIKeyboardHIDUsage.keyboardSpacebar)
                case .keyboardReturnOrEnter:
                    return usageValue(UIKeyboardHIDUsage.keyboardReturnOrEnter)
                case .keyboardEscape:
                    return usageValue(UIKeyboardHIDUsage.keyboardEscape)
                case .keyboardUpArrow:
                    return usageValue(UIKeyboardHIDUsage.keyboardUpArrow)
                case .keyboardDownArrow:
                    return usageValue(UIKeyboardHIDUsage.keyboardDownArrow)
                case .keyboardLeftArrow:
                    return usageValue(UIKeyboardHIDUsage.keyboardLeftArrow)
                case .keyboardRightArrow:
                    return usageValue(UIKeyboardHIDUsage.keyboardRightArrow)
                }
            }
            return nil
        #else
            return nil
        #endif
    }

    #if os(iOS)
        @available(iOS 13.4, *)
        private static func usageValue(_ usage: UIKeyboardHIDUsage) -> UInt16 {
            UInt16(truncatingIfNeeded: usage.rawValue)
        }
    #endif
}

#if os(macOS)
    @MainActor extension GameKeyShortcut {
        init?(event: NSEvent) {
            guard let characters = event.charactersIgnoringModifiers, characters.isEmpty == false else { return nil }
            let scalar = String(characters.prefix(1))
            self.init(characters: scalar,
                      modifiers: GameKeyModifiers(eventFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)),
                      macKeyCode: event.keyCode,
                      hidUsage: nil)
        }

        func matches(event: NSEvent) -> Bool {
            let normalizedFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard GameKeyModifiers(eventFlags: normalizedFlags) == modifiers else { return false }
            if let macKeyCode, macKeyCode == event.keyCode {
                return true
            }
            if let characters = event.charactersIgnoringModifiers?.lowercased() {
                return normalizedCharacters == String(characters.prefix(1))
            }
            return false
        }
    }
#endif

#if os(iOS)
    @MainActor extension GameKeyShortcut {
        init?(press: UIPress) {
            guard let key = press.key else { return nil }
            guard let normalizedCharacters = GameKeyShortcut.normalizedCharacters(for: key) else { return nil }
            var hidUsage: UInt16?
            if #available(iOS 13.4, *) {
                hidUsage = UInt16(truncatingIfNeeded: key.keyCode.rawValue)
            }
            self.init(characters: normalizedCharacters,
                      modifiers: GameKeyModifiers(uiFlags: key.modifierFlags),
                      macKeyCode: nil,
                      hidUsage: hidUsage)
        }

        func matches(press: UIPress) -> Bool {
            guard let key = press.key else { return false }
            guard GameKeyModifiers(uiFlags: key.modifierFlags) == modifiers else { return false }
            if let hidUsage {
                if #available(iOS 13.4, *),
                   hidUsage == UInt16(truncatingIfNeeded: key.keyCode.rawValue)
                {
                    return true
                }
            }
            guard let normalized = GameKeyShortcut.normalizedCharacters(for: key) else { return false }
            return normalizedCharacters == normalized
        }

        private static func normalizedCharacters(for key: UIKey) -> String? {
            let characters = key.charactersIgnoringModifiers
            if characters.isEmpty == false {
                switch characters {
                case UIKeyCommand.inputUpArrow:
                    return GameKeyCharacters.arrowUp
                case UIKeyCommand.inputDownArrow:
                    return GameKeyCharacters.arrowDown
                case UIKeyCommand.inputLeftArrow:
                    return GameKeyCharacters.arrowLeft
                case UIKeyCommand.inputRightArrow:
                    return GameKeyCharacters.arrowRight
                default:
                    return String(characters.lowercased().prefix(1))
                }
            }

            if #available(iOS 13.4, *) {
                switch key.keyCode {
                case .keyboardUpArrow:
                    return GameKeyCharacters.arrowUp
                case .keyboardDownArrow:
                    return GameKeyCharacters.arrowDown
                case .keyboardLeftArrow:
                    return GameKeyCharacters.arrowLeft
                case .keyboardRightArrow:
                    return GameKeyCharacters.arrowRight
                default:
                    break
                }
            }

            return nil
        }

        func makeKeyCommand(target _: Any?, action: Selector) -> UIKeyCommand? {
            guard let input = uiCommandInput else { return nil }
            let command = UIKeyCommand(input: input, modifierFlags: modifiers.uiKeyModifiers, action: action)
            command.wantsPriorityOverSystemBehavior = true
            return command
        }

        func matches(command: UIKeyCommand) -> Bool {
            guard modifiers.uiKeyModifiers == command.modifierFlags else { return false }
            guard let input = command.input else { return false }
            return uiCommandInput == input
        }

        private var uiCommandInput: String? {
            switch normalizedCharacters {
            case GameKeyCharacters.arrowUp:
                UIKeyCommand.inputUpArrow
            case GameKeyCharacters.arrowDown:
                UIKeyCommand.inputDownArrow
            case GameKeyCharacters.arrowLeft:
                UIKeyCommand.inputLeftArrow
            case GameKeyCharacters.arrowRight:
                UIKeyCommand.inputRightArrow
            case GameKeyCharacters.tab:
                "\t"
            case GameKeyCharacters.space:
                " "
            case GameKeyCharacters.escape:
                UIKeyCommand.inputEscape
            case GameKeyCharacters.carriageReturn:
                "\r"
            default:
                String(normalizedCharacters.prefix(1))
            }
        }
    }
#endif

// MARK: - Persistence

@MainActor
@Observable
final class GameKeyboardSettings {
    static let shared = GameKeyboardSettings()

    private(set) var overrides: [GameInputAction.RawValue: GameKeyShortcut] = [:]
    private let storageKey = "GameKeyboardBindings"

    init() {
        load()
    }

    func binding(for action: GameInputAction) -> GameKeyShortcut {
        activeShortcuts(for: action).first ?? action.defaultShortcuts[0]
    }

    func activeShortcuts(for action: GameInputAction) -> [GameKeyShortcut] {
        if let override = overrides[action.rawValue] {
            return [override]
        }
        return action.defaultShortcuts
    }

    func setBinding(_ action: GameInputAction, to shortcut: GameKeyShortcut) {
        overrides[action.rawValue] = shortcut
        persist()
    }

    func resetBinding(_ action: GameInputAction) {
        guard overrides[action.rawValue] != nil else { return }
        overrides.removeValue(forKey: action.rawValue)
        persist()
    }

    func resetAll() {
        guard overrides.isEmpty == false else { return }
        overrides.removeAll()
        persist()
    }

    func isUsingDefaultBinding(_ action: GameInputAction) -> Bool {
        overrides[action.rawValue] == nil
    }

    #if os(macOS)
        func action(matching event: NSEvent) -> GameInputAction? {
            for action in GameInputAction.allCases {
                for shortcut in activeShortcuts(for: action) where shortcut.matches(event: event) {
                    return action
                }
            }
            return nil
        }
    #endif

    #if os(iOS)
        func action(matching press: UIPress) -> GameInputAction? {
            for action in GameInputAction.allCases {
                for shortcut in activeShortcuts(for: action) where shortcut.matches(press: press) {
                    return action
                }
            }
            return nil
        }

        func action(matching command: UIKeyCommand) -> GameInputAction? {
            for action in GameInputAction.allCases {
                for shortcut in activeShortcuts(for: action) where shortcut.matches(command: command) {
                    return action
                }
            }
            return nil
        }
    #endif

    func action(using shortcut: GameKeyShortcut, excluding action: GameInputAction? = nil) -> GameInputAction? {
        for candidate in GameInputAction.allCases where candidate != action {
            if activeShortcuts(for: candidate).contains(shortcut) {
                return candidate
            }
        }
        return nil
    }

    func directionShortcuts(for command: GameDirectionCommand) -> [GameKeyShortcut] {
        command.defaultShortcuts
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            overrides = [:]
            return
        }
        do {
            let decoded = try JSONDecoder().decode([String: GameKeyShortcut].self, from: data)
            var updated: [GameInputAction.RawValue: GameKeyShortcut] = [:]
            for (key, shortcut) in decoded where GameInputAction(rawValue: key) != nil {
                updated[key] = shortcut
            }
            overrides = updated
        } catch {
            overrides = [:]
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(overrides)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Silently ignore persistence failures.
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let gameInputActionTriggered = Notification.Name("GameInputActionTriggered")
}

enum GameInputActionDispatcher {
    static func send(_ action: GameInputAction) {
        NotificationCenter.default.post(name: .gameInputActionTriggered, object: action)
    }
}
