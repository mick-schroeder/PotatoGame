// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI

struct LevelsSummaryView: View {
    let completedLevels: Int
    let totalLevels: Int
    let nextLevel: SchmojiLevelInfo
    let playLevel: SchmojiLevelInfo
    let playIsLocked: Bool
    let shouldShowUnlockButton: Bool
    var body: some View {
        Group {
            if hasCompletedAllLevels {
                completedContent
            } else {
                progressContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .potatoCardStyle(cornerRadius: 28)
        .padding(.top, 12)
    }
}

private extension LevelsSummaryView {
    var hasCompletedAllLevels: Bool {
        totalLevels > 0 && completedLevels >= totalLevels
    }

    var completionProgress: Double {
        guard totalLevels > 0 else { return 0 }
        return Double(completedLevels) / Double(totalLevels)
    }

    var completedContent: some View {
        VStack(alignment: .center, spacing: 16) {
            Image("Potato Game Trophy")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 100)
                .accessibilityHidden(true)

            Text(.levelsSummaryCompleteTitle)
                .font(.title3.weight(.semibold))

            Text(.levelsSummaryCompleteMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)

            Text(.levelsSummaryLevelCount(completedLevels: completedLevels, totalLevels: totalLevels))
                .font(.footnote.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    var progressContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(PotatoTheme.cardSecondaryText)
                .accessibilityHidden(true)

            Text(.levelsSummaryTitle)
                .font(.title2.weight(.bold))

            Text(.levelsSummaryLevelCount(completedLevels: completedLevels, totalLevels: totalLevels))
                .font(.headline)
                .foregroundStyle(.secondary)

            ProgressView(
                value: Double(completedLevels),
                total: max(Double(totalLevels), 1)
            ) {
                Text(.levelsSummaryProgressLabel)
                    .font(.footnote.weight(.semibold))
            } currentValueLabel: {
                Text(completionProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
            }
            .progressViewStyle(.linear)
            playButton

            if playIsLocked || shouldShowUnlockButton {
                levelPackPrompt
            } else {
                Text(.levelsSummaryKeepGoingMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var playButton: some View {
        PlayNavigationButton(level: playLevel)
            .disabled(playIsLocked)
            .opacity(playIsLocked ? 0.6 : 1)
            .overlay(alignment: .trailing) {
                if playIsLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.trailing, 12)
                }
            }
    }

    @ViewBuilder
    var levelPackPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.levelsSummaryLevelPackPrompt)
                .font(.footnote.weight(.semibold))

            Text(.levelsSummaryLevelPackDescription(baseGameLevelLimit: SchmojiOptions.baseGameLevelLimit))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let requiredPack = playLevel.requiredLevelPack {
                Text(requiredPack.displayName)
                    .font(.footnote.weight(.semibold))
            }

            LevelStoreNavigationButton(requiredPack: playLevel.requiredLevelPack)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct PlayNavigationButton: View {
    let level: SchmojiLevelInfo
    @Environment(\.router) private var router
    @AppStorage("haptics") private var hapticsEnabled: Bool = SchmojiOptions.haptics

    var body: some View {
        Button {
            HapticsCoordinator.impact(.heavy, enabled: hapticsEnabled)
            router.navigate(to: level)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")

                Text(.buttonPlay)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .foregroundStyle(PotatoTheme.buttonText)
        }
        .tint(PotatoTheme.button)
        .glassButtonStyle(prominent: true)
        .accessibilityLabel(Text(.accessibilityLevelsPlayNext))
    }
}

private struct LevelStoreNavigationButton: View {
    let requiredPack: LevelPackDefinition?
    @Environment(\.router) private var router
    @AppStorage("haptics") private var hapticsEnabled: Bool = SchmojiOptions.haptics

    var body: some View {
        Button {
            HapticsCoordinator.notification(.warning, enabled: hapticsEnabled)
            router.navigate(to: .store)
        } label: {
            Text(LocalizedStringResource("button.visit-store", defaultValue: "Visit Level Store"))
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(6)
        }
        .buttonStyle(.borderedProminent)
        .tint(PotatoTheme.button)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        if let requiredPack {
            let packName = String(localized: requiredPack.displayName)
            return Text("Open Store to unlock \(packName)")
        }
        return Text(LocalizedStringResource("accessibility.levels.visit-store", defaultValue: "Open Level Store"))
    }
}

#Preview("Levels Summary – Progress") {
    LevelsSummaryView(
        completedLevels: 18,
        totalLevels: 64,
        nextLevel: .preview(levelNumber: 19),
        playLevel: .preview(levelNumber: 19),
        playIsLocked: false,
        shouldShowUnlockButton: false
    )
    .padding()
    .environment(PreviewSampleData.makeLevelPackStore())
}

#Preview("Levels Summary – Win") {
    LevelsSummaryView(
        completedLevels: 64,
        totalLevels: 64,
        nextLevel: .preview(levelNumber: 19),
        playLevel: .preview(levelNumber: 19),
        playIsLocked: false,
        shouldShowUnlockButton: false
    )
    .padding()
    .environment(PreviewSampleData.makeLevelPackStore())
}

#Preview("Levels Summary – Locked") {
    LevelsSummaryView(
        completedLevels: 24,
        totalLevels: 64,
        nextLevel: .preview(levelNumber: 25),
        playLevel: .preview(levelNumber: 25),
        playIsLocked: true,
        shouldShowUnlockButton: true
    )
    .padding()
    .environment(PreviewSampleData.makeLevelPackStore())
}

private extension SchmojiLevelInfo {
    static func preview(levelNumber: Int) -> SchmojiLevelInfo {
        SchmojiLevelInfo(
            levelNumber: levelNumber,
            levelBackgroundColor: .green,
            potentialPotatoCount: 5
        )
    }
}
