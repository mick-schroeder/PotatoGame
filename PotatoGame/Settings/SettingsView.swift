// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI
#if os(iOS)
    import UIKit
#endif

struct SettingsView: View {
    @Query
    private var accounts: [Account]

    @State private var presentingPassSheet = false
    @State private var showingNewGameConfirmation = false
    @State private var editingAction: GameInputAction?
    @State private var conflictAction: GameInputAction?
    @State private var conflictShortcut: GameKeyShortcut?
    @State private var showingConflictAlert = false

    #if os(iOS)
        @State private var presentingManagePassSheet = false
    #elseif os(macOS)
        @Environment(\.openURL) private var openURL
    #endif

    @AppStorage("sound") var sound: Bool = PotatoGameOptions.sound
    @AppStorage("haptics") var haptics: Bool = PotatoGameOptions.haptics
    @AppStorage("gamecenter") var gameCenter: Bool = PotatoGameOptions.gameCenter

    @Environment(GameKeyboardSettings.self) private var keyboardSettings

    private var supportsKeyboardRemapping: Bool {
        #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad
        #else
            return true
        #endif
    }

    var body: some View {
        if let account = accounts.first {
            Form {
                VStack {
                    PotatoCountView()

                    Text(.settingsJoinedOn(account.joinDate.formatted(.dateTime.month(.wide).day(.twoDigits).year())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowInsets(.none)
                .listRowBackground(Color.clear)

                Section {
                    Toggle(isOn: $sound) {
                        Label {
                            Text(.settingsSound)
                        } icon: {
                            Image(systemName: sound ? "speaker.fill" : "speaker.slash.fill")
                        }
                    }
                    Toggle(isOn: $haptics) {
                        Label {
                            Text(.settingsHaptics)
                        } icon: {
                            Image(systemName: haptics ? "apple.haptics.and.music.note" : "apple.haptics.and.music.note.slash")
                        }
                    }
                    Toggle(isOn: $gameCenter) {
                        Label {
                            Text(.settingsGameCenter)
                        } icon: {
                            Image(systemName: gameCenter ? "person" : "person.slash")
                        }
                    }
                }

                if supportsKeyboardRemapping {
                    keyboardControlsSection
                    directionControlsSection
                }

                Section {
                    Link(destination: URL(string: "https://www.mickschroeder.com/schmoji")!) {
                        Text(.buttonReviewOnAppStore)
                    }
                }
                Section {
                    Text(.developerCompanyName)
                    Link(destination: URL(string: "mailto:contact@mickschroeder.com")!) {
                        Text(verbatim: "contact@mickschroeder.com")
                    }
                    Link(destination: URL(string: "https://www.mickschroeder.com")!) {
                        Text(verbatim: "https://mickschroeder.com")
                    }
                }

                Section {
                    Text(.settingsDisclaimer)
                    Link(destination: URL(string: "https://github.com/mick-schroeder/PotatoGame")!) {
                        Text(.sourceCode)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingNewGameConfirmation = true
                    } label: {
                        Label {
                            Text(.buttonNewGame)
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                }
            }
            .potatoBackground()
            .formStyle(.grouped)
            .alert(SettingsStrings.confirmNewGameTitle, isPresented: $showingNewGameConfirmation) {
                Button(role: .destructive) {
                    NotificationCenter.default.post(name: .newGameRequested, object: nil)
                } label: {
                    Text(SettingsStrings.confirmNewGameConfirm)
                }

                Button(role: .cancel) {
                    showingNewGameConfirmation = false
                } label: {
                    Text(SettingsStrings.confirmNewGameCancel)
                }
            } message: {
                Text(SettingsStrings.confirmNewGameMessage)
            }
            .navigationTitle(Text(.navigationSettings))
            .sheet(item: $editingAction) { action in
                KeyboardBindingCaptureView(action: action) { shortcut in
                    applyShortcut(shortcut, to: action)
                    editingAction = nil
                } onCancel: {
                    editingAction = nil
                }
            }
            .alert("Keyboard Shortcut In Use", isPresented: $showingConflictAlert) {
                Button(role: .cancel) {
                    showingConflictAlert = false
                    conflictAction = nil
                    conflictShortcut = nil
                } label: {
                    Text("OK")
                }
            } message: {
                if let conflictAction, let conflictShortcut {
                    Text(
                        LocalizedStringResource(
                            "settings.keyboard.shortcutConflict",
                            defaultValue: "\(conflictShortcut.displayLabel) is already assigned to \(conflictAction.title). Change that action first."
                        )
                    )
                } else {
                    Text("That shortcut is already assigned. Change the other binding first.")
                }
            }

        } else {
            ContentUnavailableView(.settingsNoAccount, systemImage: "capsule")
        }
    }

    private var keyboardControlsSection: some View {
        Section("Keyboard Controls") {
            ForEach(GameInputAction.allCases) { action in
                KeyboardBindingRow(
                    action: action,
                    primaryShortcut: keyboardSettings.binding(for: action),
                    additionalShortcuts: keyboardSettings.isUsingDefaultBinding(action) ? Array(keyboardSettings.activeShortcuts(for: action).dropFirst()) : [],
                    canReset: keyboardSettings.isUsingDefaultBinding(action) == false,
                    onChange: { editingAction = action },
                    onReset: { keyboardSettings.resetBinding(action) }
                )
            }

            Button(role: .destructive) {
                keyboardSettings.resetAll()
            } label: {
                Text("Reset All Shortcuts")
            }
            .disabled(keyboardSettings.overrides.isEmpty)
        }
    }

    private var directionControlsSection: some View {
        Section("Movement Controls") {
            ForEach(GameDirectionCommand.allCases) { command in
                KeyboardInfoRow(
                    title: command.title,
                    detail: command.detail,
                    shortcuts: keyboardSettings.directionShortcuts(for: command)
                )
            }
        }
    }

    private func applyShortcut(_ shortcut: GameKeyShortcut, to action: GameInputAction) {
        if let conflict = keyboardSettings.action(using: shortcut, excluding: action) {
            conflictAction = conflict
            conflictShortcut = shortcut
            showingConflictAlert = true
            return
        }

        keyboardSettings.setBinding(action, to: shortcut)
    }
}

private struct KeyboardBindingRow: View {
    var action: GameInputAction
    var primaryShortcut: GameKeyShortcut
    var additionalShortcuts: [GameKeyShortcut]
    var canReset: Bool
    var onChange: () -> Void
    var onReset: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if additionalShortcuts.isEmpty == false {
                    Text("Also: \(additionalShortcuts.map(\.displayLabel).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Button(action: onChange) {
                ShortcutCapsule(text: primaryShortcut.displayLabel)
            }
            .buttonStyle(.bordered)

            if canReset {
                Button("Reset", action: onReset)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

private struct KeyboardInfoRow: View {
    var title: LocalizedStringResource
    var detail: LocalizedStringResource
    var shortcuts: [GameKeyShortcut]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                ForEach(shortcuts, id: \.self) { shortcut in
                    ShortcutCapsule(text: shortcut.displayLabel)
                        .accessibilityLabel("Shortcut \(shortcut.displayLabel)")
                }
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

private struct ShortcutCapsule: View {
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
            Text(text)
                .font(.body.monospaced())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private enum SettingsStrings {
    static let confirmNewGameTitle = LocalizedStringResource.settingsConfirmNewGameTitle

    static let confirmNewGameMessage = LocalizedStringResource.settingsConfirmNewGameMessage

    static let confirmNewGameConfirm = LocalizedStringResource.settingsConfirmNewGameConfirm

    static let confirmNewGameCancel = LocalizedStringResource.settingsConfirmNewGameCancel
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewSampleData.makeContainer())
    .environment(GameKeyboardSettings())
}
