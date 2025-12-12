// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI

/// Unified end-of-level sheet for both win and lose outcomes.
struct PotatoGameEndView: View {
    enum Outcome {
        case win(perfect: Bool, unlockProgress: EmojiSelection.UnlockProgress?, potatoesEarned: Int)
        case lose
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var level: PotatoGameLevelInfo
    var outcome: Outcome
    var isNextLevelAvailable: Bool = false
    var onReplay: (() -> Void)?
    var onNextLevel: (() -> Void)?
    var onQuit: (() -> Void)?

    private var cardEmphasis: PotatoGameEndCard.Emphasis {
        switch outcome {
        case let .win(perfect, _, _):
            perfect ? .celebration : .success
        case .lose:
            .failure
        }
    }

    private var iconSystemName: String {
        switch outcome {
        case let .win(perfect, _, _):
            perfect ? GameState.winPerfect.iconSystemName : GameState.win.iconSystemName
        case .lose:
            GameState.lose.iconSystemName
        }
    }

    private var sheetTitle: LocalizedStringResource {
        .levelsTileTitle(level.levelNumber)
    }

    private var statusTitle: LocalizedStringResource {
        switch outcome {
        case let .win(perfect, _, _):
            if perfect {
                .levelsStatusPerfect
            } else {
                .levelsStatusCompleted
            }
        case .lose:
            .levelsStatusLost
        }
    }

    var body: some View {
        PotatoGameEndCard(
            emphasis: cardEmphasis,
            iconSystemName: iconSystemName,
            title: sheetTitle,
            headerContent: { badge, _ in
                summarySection(badge: badge, status: statusTitle)
            },
            actionsContent: {
                actionsSection
            }
        )
    }
}

private extension PotatoGameEndView {
    @ViewBuilder
    func summarySection(badge: PotatoGameEndCard.BadgeView, status: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                badge
                Text(status)
                    .font(.system(.largeTitle, design: .rounded).weight(.black))
                    .foregroundStyle(cardEmphasis.tint)
                Spacer()
            }
            switch outcome {
            case let .win(perfect, unlock, potatoes):
                winSummarySection(isPerfect: perfect, unlockProgress: unlock, potatoesEarned: potatoes)
            case .lose:
                loseSummarySection(badge: badge)
            }
        }
    }

    func winSummarySection(
        isPerfect: Bool,
        unlockProgress: EmojiSelection.UnlockProgress?,
        potatoesEarned: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                Spacer()

                Label {
                    Text("+\(potatoesEarned)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                } icon: {
                    Image("Cool Potato")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 3)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(
                    Text(.gameEndPotatoesEarned)
                )
                .accessibilityValue(Text("\(potatoesEarned)"))

                Spacer()
            }

            if isPerfect, let unlockProgress {
                unlockProgressSection(for: unlockProgress)
            }
        }
    }

    func loseSummarySection(badge _: PotatoGameEndCard.BadgeView) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                Spacer()
            }
        }
    }

    @ViewBuilder
    var actionsSection: some View {
        VStack(spacing: 14) {
            Button {
                dismiss()
                onNextLevel?()
            } label: {
                Label {
                    Text(.buttonNext)
                } icon: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .frame(maxWidth: .infinity)
                .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.accentColor)
            .disabled(isNextLevelAvailable == false)

            Button {
                dismiss()
                onReplay?()
            } label: {
                Label {
                    Text(.buttonReplay)
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .frame(maxWidth: .infinity)
                .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                dismiss()
                onQuit?()
            } label: {
                Label {
                    Text(.buttonHome)
                } icon: {
                    Image(systemName: "house.fill")
                }
                .frame(maxWidth: .infinity)
                .font(.headline)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    func unlockProgressSection(for progress: EmojiSelection.UnlockProgress) -> some View {
        if progress.totalSchmojis > 1 {
            let accent = progress.color.color

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label {
                        Text(progress.color.localizedName)
                            .font(.headline)
                    } icon: {
                        Circle()
                            .fill(accent)
                            .frame(width: 18, height: 18)
                    }

                    Spacer(minLength: 8)

                    Label {
                        Text(.unlockProgressCounter(progress.winsTowardNextUnlock, progress.winsRequired)
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "flag.checkered")
                            .imageScale(.small)
                    }
                }

                ProgressView(value: min(max(progress.progressFraction, 0), 1))
                    .tint(accent)

                if progress.didUnlockThisRun, let unlockedHex = progress.unlockedHexThisRun {
                    HStack(spacing: 12) {
                        PotatoGameArt.image(forHexcode: unlockedHex)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: accent.opacity(0.22), radius: 8, x: 0, y: 4)

                        Label {
                            Text(.unlockProgressUnlocked)
                                .font(.headline)
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accent.opacity(colorScheme == .dark ? 0.2 : 0.12))
            )
        }
    }
}

// MARK: - Card Shell

struct PotatoGameEndCard: View {
    enum Emphasis {
        case success
        case failure
        case celebration

        var tint: Color {
            switch self {
            case .success: .schmojiGreen
            case .failure: .schmojiRed
            case .celebration: .schmojiOrange
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private let headerContent: AnyView
    private let actionsContent: AnyView
    private let title: LocalizedStringResource
    private let onDismissTapped: (() -> Void)?

    init(
        emphasis: Emphasis,
        iconSystemName: String,
        title: LocalizedStringResource,
        @ViewBuilder headerContent: (_ badge: BadgeView, _ title: LocalizedStringResource) -> some View,
        @ViewBuilder actionsContent: () -> some View,
        onDismissTapped: (() -> Void)? = nil
    ) {
        let badge = BadgeView(emphasis: emphasis, iconSystemName: iconSystemName)
        self.headerContent = AnyView(headerContent(badge, title))
        self.actionsContent = AnyView(actionsContent())
        self.title = title
        self.onDismissTapped = onDismissTapped
    }

    var body: some View {
        NavigationStack {
            ViewThatFits(in: .vertical) {
                cardLayout

                ScrollView {
                    cardLayout
                        .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal)
            .safeAreaPadding(.bottom)
            .frame(maxWidth: .infinity, alignment: .center)
            .navigationTitle(Text(title))
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    #if os(iOS)
                        ToolbarItem(placement: .topBarTrailing) {
                            DismissButton(onTap: onDismissTapped)
                        }
                    #else
                        ToolbarItem {
                            DismissButton(onTap: onDismissTapped)
                        }
                    #endif
                }
        }
    }

    @ViewBuilder
    private var cardLayout: some View {
        VStack(spacing: 24) {
            headerContent
                .frame(maxWidth: .infinity, alignment: .leading)

            actionsContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 24)
    }
}

extension PotatoGameEndCard {
    struct BadgeView: View {
        let emphasis: Emphasis
        let iconSystemName: String

        var body: some View {
            Image(systemName: iconSystemName)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [
                                emphasis.tint.opacity(0.95),
                                emphasis.tint.opacity(0.7),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .shadow(color: emphasis.tint.opacity(0.28), radius: 8, x: 0, y: 5)
        }
    }
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            dismiss()
            onTap?()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(6)
                .contentShape(.circle)
        }
        .accessibilityLabel(Text(.buttonClose))
    }
}

#Preview("Game End – Perfect Win") {
    PotatoGameEndView(
        level: PreviewSampleData.sampleLevel(levelNumber: 4, state: .winPerfect, potatoes: 12),
        outcome: .win(
            perfect: true,
            unlockProgress: PreviewSampleData.sampleUnlockProgress(),
            potatoesEarned: 12
        ),
        isNextLevelAvailable: true
    )
}

#Preview("Game End – Lose") {
    PotatoGameEndView(
        level: PreviewSampleData.sampleLevel(levelNumber: 5, state: .lose, potatoes: 3),
        outcome: .lose,
        isNextLevelAvailable: false
    )
    .preferredColorScheme(.dark)
}

#Preview("Game End Card Shell") {
    PotatoGameEndCard(
        emphasis: .success,
        iconSystemName: "trophy.fill",
        title: "Preview Level"
    ) { badge, _ in
        HStack(spacing: 12) {
            badge
            VStack(alignment: .leading) {
                Text("Preview Header")
                    .font(.title2.weight(.semibold))
                Text("Use this space to describe the result.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    } actionsContent: {
        VStack(spacing: 12) {
            Button("Next Level", action: {})
                .buttonStyle(.borderedProminent)
            Button("Replay Level", action: {})
                .buttonStyle(.bordered)
        }
    }
}
