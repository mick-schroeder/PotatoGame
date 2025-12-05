// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI

#if os(iOS) || os(tvOS) || os(visionOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

struct LevelsGridItem: View {
    let level: SchmojiLevelInfo
    @Environment(LevelPackStore.self) private var levelPackStore
    @Environment(\.router) private var router
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("haptics") private var hapticsEnabled: Bool = SchmojiOptions.haptics
    @ScaledMetric(relativeTo: .title2) private var badgeSize: CGFloat = 64

    private let tileCornerRadius: CGFloat = 24

    private var accentColor: Color { accentColor(for: level.gameState) }
    private var levelNumberDisplay: String {
        level.levelNumber.formatted(.number.grouping(.automatic))
    }

    private var badgeNumberDigitCount: Int {
        String(level.levelNumber).count
    }

    private var badgeNumberFontScale: CGFloat {
        let base: CGFloat = 0.34
        let decrement: CGFloat = 0.06
        let extraDigits = max(0, badgeNumberDigitCount - 3)
        return max(0.22, base - CGFloat(extraDigits) * decrement)
    }

    var body: some View {
        tileBody()
    }

    @ViewBuilder
    private func tileBody() -> some View {
        if level.isPlayable || level.isLost {
            Button {
                HapticsCoordinator.impact(.medium, enabled: hapticsEnabled)
                router.navigate(to: level)
            } label: {
                interactiveTile
            }
            .buttonStyle(.plain)
            .contentShape(.containerRelative)
            #if os(macOS)
                .focusEffectDisabled()
            #endif
        } else if level.isLevelPackLocked {
            Button(action: initiatePurchase) {
                interactiveTile
                    .overlay(alignment: .top) {
                        if levelPackStore.purchaseInProgress {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                        }
                    }
                    .opacity(0.95)
                    .grayscale(0.15)
            }
            .buttonStyle(.plain)
            .disabled(levelPackStore.purchaseInProgress || levelPackStore.isLoading)
            .contentShape(.containerRelative)
            .accessibilityLabel(Text(.accessibilityLevelsUnlockLevelPack))
        } else {
            interactiveTile
                .opacity(0.8)
                .grayscale(0.35)
        }
    }

    private var interactiveTile: some View {
        tileContent
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .top)
            .background(tileBackground)
            .contentShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
    }

    private var levelLabel: LocalizedStringResource {
        .levelsTileTitle(level.levelNumber)
    }

    private var tileContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                levelBadge
                    .frame(width: badgeSize, height: badgeSize)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 28)

            Spacer(minLength: 0)

            levelStatusFooter
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel(for: level.gameState)))
        .accessibilityHint(level.isLevelPackLocked ? Text(.accessibilityLevelsHintLocked) : Text(.accessibilityLevelsHintTapToPlay))
    }

    private var levelStatusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(levelLabel)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(statusFooterTitleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)

            Text(statusLabel(for: level.gameState))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(statusFooterSubtitleColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            BottomRoundedRectangle(radius: tileCornerRadius)
                .fill(statusFooterBackground)
                .overlay {
                    BottomRoundedRectangle(radius: tileCornerRadius)
                        .stroke(statusFooterBorderColor, lineWidth: 1)
                }
        }
        .accessibilityIdentifier("LevelsGridItem.statusFooter")
    }

    private var levelBadge: some View {
        ZStack {
            Circle()
                .fill(badgeBackgroundStyle)
                .overlay {
                    Circle()
                        .strokeBorder(badgeBorderColor, lineWidth: 1)
                }
                .shadow(color: badgeShadowColor, radius: 6, x: 0, y: 4)

            badgeSymbol
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var badgeSymbol: some View {
        if level.isLevelPackLocked {
            Image(systemName: level.gameState.iconSystemName)
                .font(.system(size: badgeSize * 0.34, weight: .semibold))
                .foregroundStyle(badgeForegroundColor.opacity(0.85))
        } else {
            switch level.gameState {
            case .winPerfect:
                Image(systemName: level.gameState.iconSystemName)
                    .font(.system(size: badgeSize * 0.34, weight: .semibold))
                    .foregroundStyle(badgeForegroundColor)
            case .win:
                Image(systemName: level.gameState.iconSystemName)
                    .font(.system(size: badgeSize * 0.34, weight: .semibold))
                    .foregroundStyle(badgeForegroundColor)
            case .lose:
                Image(systemName: level.gameState.iconSystemName)
                    .font(.system(size: badgeSize * 0.34, weight: .semibold))
                    .foregroundStyle(badgeForegroundColor)
            default:
                Text(levelNumberDisplay)
                    .font(.system(size: badgeSize * badgeNumberFontScale, weight: .heavy, design: .rounded))
                    .foregroundStyle(badgeForegroundColor)
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .allowsTightening(true)
            }
        }
    }

    private func accessibilityLabel(for state: GameState) -> LocalizedStringResource {
        switch state {
        case .newUnlocked: .accessibilityLevelStateNew
        case .playing: .levelsStatusInProgress
        case .win: .accessibilityLevelStateCompleted
        case .lose: .accessibilityLevelStateLost
        case .newLevelPack: LocalizedStringResource.accessibilityLevelStateLevelPack
        case .winPerfect: .accessibilityLevelStatePerfect
        }
    }

    private func statusLabel(for state: GameState) -> LocalizedStringResource {
        switch state {
        case .newUnlocked: .levelsStatusNew
        case .playing: .levelsStatusInProgress
        case .win: .levelsStatusCompleted
        case .lose: .levelsStatusLost
        case .newLevelPack: LocalizedStringResource.levelsStatusLevelPack
        case .winPerfect: .levelsStatusPerfect
        }
    }

    private func accentColor(for state: GameState) -> Color {
        switch state {
        case .playing, .newUnlocked:
            level.levelBackgroundColor.color
        case .win:
            .schmojiGreen
        case .lose:
            .schmojiRed
        case .newLevelPack:
            .schmojiBrown
        case .winPerfect:
            .schmojiOrange
        }
    }

    private var tileBackground: some View {
        let shape = RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)

        return shape
            .fill(tileBaseFill)
            .overlay {
                shape
                    .fill(tileStateGradient)
            }
            .overlay {
                shape
                    .strokeBorder(tileBorderGradient, lineWidth: tileStrokeWidth)
            }
            .shadow(color: tileShadowColor, radius: tileShadowRadius, x: 0, y: tileShadowYOffset)
    }

    private var tileStrokeWidth: CGFloat {
        level.isCompleted || level.isLost ? 4 : 1.5
    }

    private var tileBaseFill: LinearGradient {
        let colors: [Color]
        if level.isCompleted {
            let top = accentColor.opacity(colorScheme == .dark ? 0.65 : 0.9)
            let bottom = accentColor.opacity(colorScheme == .dark ? 0.4 : 0.7)
            colors = [top, bottom]
        } else {
            colors = [tileBaseTopColor, tileBaseBottomColor]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var tileBorderGradient: LinearGradient {
        if level.isCompleted || level.isLost {
            LinearGradient(
                colors: [
                    accentColor.opacity(1),
                    accentColor.opacity(0.9),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.15 : 0.55),
                    accentColor.opacity(0.75),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var tileShadowColor: Color {
        accentColor.opacity(0.18)
    }

    private var tileShadowRadius: CGFloat {
        3
    }

    private var tileShadowYOffset: CGFloat {
        colorScheme == .dark ? 4 : 6
    }

    private var tileStateGradient: RadialGradient {
        if level.isCompleted || level.isLost {
            RadialGradient(
                gradient: Gradient(colors: [
                    accentColor.opacity(1),
                    accentColor.opacity(1),
                    accentColor.opacity(1),
                ]),
                center: .topLeading,
                startRadius: 12,
                endRadius: 320
            )
        } else {
            RadialGradient(
                gradient: Gradient(colors: [
                    accentColor.opacity(0.7),
                    accentColor.opacity(0.7 * 0.35),
                    accentColor.opacity(0),
                ]),
                center: .topLeading,
                startRadius: 12,
                endRadius: 320
            )
        }
    }

    private var statusFooterBackground: LinearGradient {
        let topOpacity = colorScheme == .dark ? 0.95 : 1
        let bottomOpacity = colorScheme == .dark ? 0.75 : 0.88
        let modifier = level.isLevelPackLocked ? 0.6 : 1

        return LinearGradient(
            colors: [
                accentColor.opacity(topOpacity * modifier),
                accentColor.opacity(bottomOpacity * modifier),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusFooterBorderColor: Color {
        accentColor.opacity(level.isLevelPackLocked ? 0.4 : 0.65)
    }

    private var statusFooterTitleColor: Color {
        Color.white.opacity(level.isLevelPackLocked ? 0.85 : 0.8)
    }

    private var statusFooterSubtitleColor: Color {
        Color.white.opacity(level.isLevelPackLocked ? 0.7 : 0.8)
    }

    private var badgeBackgroundStyle: LinearGradient {
        LinearGradient(
            colors: [
                accentColor.opacity(colorScheme == .dark ? 0.78 : 0.88),
                accentColor.opacity(colorScheme == .dark ? 0.58 : 0.68),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var badgeBorderColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.25 : 0.4)
    }

    private var badgeShadowColor: Color {
        accentColor.opacity(0.15)
    }

    private var badgeForegroundColor: Color {
        Color.white.opacity(0.9)
    }

    #if os(macOS)
        private var tileBaseTopColor: Color {
            let color = colorScheme == .dark ? NSColor.controlBackgroundColor : NSColor.windowBackgroundColor
            return Color(nsColor: color).opacity(colorScheme == .dark ? 0.8 : 1)
        }

        private var tileBaseBottomColor: Color {
            let color = colorScheme == .dark ? NSColor.windowBackgroundColor : NSColor.controlBackgroundColor
            return Color(nsColor: color).opacity(colorScheme == .dark ? 0.65 : 0.9)
        }
    #else
        private var tileBaseTopColor: Color {
            let color = UIColor.secondarySystemBackground
            return Color(color)
        }

        private var tileBaseBottomColor: Color {
            let color = UIColor.systemBackground
            return Color(color)
        }
    #endif
}

private struct BottomRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clampedRadius = max(0, min(radius, min(rect.width, rect.height) / 2))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - clampedRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - clampedRadius, y: rect.maxY - clampedRadius),
            radius: clampedRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + clampedRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + clampedRadius, y: rect.maxY - clampedRadius),
            radius: clampedRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

// MARK: - Actions

private extension LevelsGridItem {
    func initiatePurchase() {
        Task {
            if let requiredPack = level.requiredLevelPack {
                await levelPackStore.purchase(pack: requiredPack)
            } else {
                await levelPackStore.purchasePrimaryPack()
            }
        }
    }
}

#Preview("Level Tile States") {
    let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 16),
    ]

    NavigationStack {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(PreviewSampleData.sampleLevels()) { level in
                    LevelsGridItem(level: level)
                        .frame(maxWidth: 140)
                }
            }
            .padding()
        }
    }
    .environment(PreviewSampleData.makeLevelPackStore())
    .padding()
    .background(Color.appBackground)
}
