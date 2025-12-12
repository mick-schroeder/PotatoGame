// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import UIKit
#endif
import SwiftData
import SwiftUI

struct HowToPlayView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(GameKeyboardSettings.self) private var keyboardSettings
    @MainActor
    private var sideInset: CGFloat { hSize == .compact ? 16 : 24 }

    private var showsKeyboardHelp: Bool {
        #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad
        #else
            return true
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    Link(destination: URL(string: "https://mickschroeder.com")!) {
                        Text("developer.hero_link")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    Text("app.name")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                }.foregroundStyle(PotatoTheme.accent)

                PotatoGameLegendView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .potatoCardStyle(cornerRadius: 24)

                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        InstructionSection(
                            title: LocalizedStringResource("how_to.play.title"),
                            systemImage: "gamecontroller.fill",
                            text: LocalizedStringResource("how_to.play.body")
                        )
                        InstructionSection(
                            title: LocalizedStringResource("how_to.goal.title"),
                            systemImage: "trophy.fill",
                            text: LocalizedStringResource("how_to.goal.body")
                        )
                        InstructionSection(
                            title: LocalizedStringResource("how_to.controls.title"),
                            systemImage: "hand.tap.fill",
                            text: LocalizedStringResource("how_to.controls.body")
                        )
                        if showsKeyboardHelp {
                            KeyboardShortcutsSection(keyboardSettings: keyboardSettings)
                        }
                        InstructionSection(
                            title: LocalizedStringResource("how_to.collection.title"),
                            systemImage: "sparkles",
                            text: .howToCollectionBody
                        )
                        InstructionSection(
                            title: LocalizedStringResource("how_to.tip.title"),
                            systemImage: "lightbulb.max.fill",
                            text: LocalizedStringResource("how_to.tip.body")
                        )
                    }
                    .padding(EdgeInsets(top: 16,
                                        leading: sideInset,
                                        bottom: 16,
                                        trailing: sideInset))
                    .potatoCardStyle(cornerRadius: 24)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: CGFloat(PotatoGameOptions.width))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .potatoBackground()
        .navigationTitle(Text("navigation.how_to_play"))
    }
}

private struct InstructionSection: View {
    let title: LocalizedStringResource
    let systemImage: String
    let text: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
            }
            .font(.headline)
            .foregroundStyle(PotatoTheme.cardSecondaryText)
            Capsule().fill(.tertiary).frame(height: 2)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

#Preview("How To Play") {
    NavigationStack {
        HowToPlayView()
    }
}

private struct KeyboardShortcutsSection: View {
    let keyboardSettings: GameKeyboardSettings

    private func shortcutLine(_ shortcuts: [GameKeyShortcut]) -> String {
        shortcuts.map(\.displayLabel).joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Keyboard & Controls")
            } icon: {
                Image(systemName: "keyboard")
            }
            .font(.headline)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Actions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(GameInputAction.allCases) { action in
                    ShortcutRow(
                        title: Text(action.title),
                        shortcuts: shortcutLine(keyboardSettings.activeShortcuts(for: action))
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Movement")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(GameDirectionCommand.allCases) { command in
                    ShortcutRow(
                        title: Text(command.title),
                        shortcuts: shortcutLine(keyboardSettings.directionShortcuts(for: command))
                    )
                }
            }
        }
    }
}

private struct ShortcutRow: View {
    let title: Text
    let shortcuts: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(shortcuts)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
