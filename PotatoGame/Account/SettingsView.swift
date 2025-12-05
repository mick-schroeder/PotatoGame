// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query
    private var accounts: [Account]

    @State private var presentingPassSheet = false
    @State private var showingNewGameConfirmation = false

    #if os(iOS)
        @State private var presentingManagePassSheet = false
    #elseif os(macOS)
        @Environment(\.openURL) private var openURL
    #endif

    @AppStorage("sound") var sound: Bool = SchmojiOptions.sound
    @AppStorage("haptics") var haptics: Bool = SchmojiOptions.haptics

    @AppStorage("gamecenter") var gameCenter: Bool = SchmojiOptions.gameCenter

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
            .formStyle(.grouped)
            .alert(SettingsStrings.confirmNewGameTitle, isPresented: $showingNewGameConfirmation) {
                Button(role: .destructive) {
                    NotificationCenter.default.post(name: .newGameRequested, object: nil)
                } label: {
                    Text(SettingsStrings.confirmNewGameConfirm)
                }

                Button(role: .cancel, action: {})
            } message: {
                Text(SettingsStrings.confirmNewGameMessage)
            }
            .navigationTitle(Text(.navigationSettings))

        } else {
            ContentUnavailableView(.settingsNoAccount, systemImage: "capsule")
        }
    }
}

private enum SettingsStrings {
    static let confirmNewGameTitle = LocalizedStringResource(
        "settings.confirm-new-game.title",
        defaultValue: "Start a new game?"
    )

    static let confirmNewGameMessage = LocalizedStringResource(
        "settings.confirm-new-game.message",
        defaultValue: "Starting a new game will reset your current progress."
    )

    static let confirmNewGameConfirm = LocalizedStringResource(
        "settings.confirm-new-game.confirm",
        defaultValue: "Start New Game"
    )
}
