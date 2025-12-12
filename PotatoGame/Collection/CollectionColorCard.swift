// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI

struct CollectionColorCard: View {
    let color: PotatoColor
    let selection: EmojiSelection?
    let updateSelection: (EmojiSelection, String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let progress = selection?.currentUnlockProgress()
        let unlocked = progress?.unlockedCount ?? 0
        let total = progress?.totalSchmojis ?? color.schmojis.count
        let accent: Color = color.color

        return VStack(alignment: .leading, spacing: 16) {
            header(unlocked: unlocked, total: total)

            if let selection {
                VStack(alignment: .center, spacing: 12) {
                    CollectionCircleView(color: color, hexcode: selection.displayHexcode())
                        .frame(minWidth: 48, idealWidth: 64, maxWidth: 72, minHeight: 48, idealHeight: 64, maxHeight: 72)

                    if let progress, progress.hasRemainingUnlocks {
                        ProgressView(value: progress.progressFraction) {
                            Text(.collectionDetailNextUnlock(progress.remainingToNextUnlock))
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .progressViewStyle(.linear)
                        .tint(PotatoTheme.button)
                    }

                    VStack {
                        selectionGrid(selection: selection, accent: accent)
                            .padding()
                    }
                    .background(.background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            } else {
                CollectionCircleView(color: color, hexcode: color.schmojis.first ?? PotatoGameOptions.potatoHex)
                    .frame(minWidth: 48, idealWidth: 64, maxWidth: 72, minHeight: 48, idealHeight: 64, maxHeight: 72)
            }
        }
        .padding(20)
        .background(.background.quinary)
        .glassedCard(cornerRadius: 30, interactive: true)
        // .shadow(color: PotatoTheme.separator.opacity(colorScheme == .dark ? 0.35 : 0.2), radius: 10, x: 0, y: 6)
        .foregroundStyle(color.color)
        .backgroundStyle(color.color)
    }
}

private extension CollectionColorCard {
    func header(unlocked: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(color.localizedName)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Text(.collectionDetailUnlockedCount(unlocked, total))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    func selectionGrid(selection: EmojiSelection, accent: Color) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 10) {
            ForEach(selection.availableHexes, id: \.self) { hex in
                Button {
                    updateSelection(selection, hex)
                } label: {
                    VStack(spacing: 6) {
                        CollectionCircleView(color: color, hexcode: hex)
                            .frame(minWidth: 48, idealWidth: 64, maxWidth: 72, minHeight: 48, idealHeight: 64, maxHeight: 72)

                        let isSelected = selection.displayHexcode() == hex
                        let isLocked = selection.isUnlocked(hex) == false

                        Image(systemName: statusIcon(selection: selection, hex: hex))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(
                                isSelected ? accent :
                                    (isLocked ? .secondary : .primary)
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(selection.isUnlocked(hex) == false)
                .opacity(selection.isUnlocked(hex) ? 1 : 0.38)
            }
        }
        .padding(.horizontal, 4)
    }

    func statusIcon(selection: EmojiSelection, hex: String) -> String {
        if selection.displayHexcode() == hex { return "checkmark.circle.fill" }
        if selection.isUnlocked(hex) == false { return "lock.fill" }
        return "circle"
    }
}

private enum CollectionPreviewFactory {
    static func selection(color: PotatoColor, unlockedCount: Int) -> EmojiSelection {
        let selection = EmojiSelection(color: color)
        let unlockedHexes = Array(selection.availableHexes.prefix(unlockedCount))
        unlockedHexes.forEach { selection.unlock(hexcode: $0) }
        selection.selectedHex = unlockedHexes.first ?? selection.displayHexcode()
        selection.perfectWinCount = unlockedCount * 2
        return selection
    }
}

#Preview("Color Card – Progress") {
    let selection = CollectionPreviewFactory.selection(color: .orange, unlockedCount: 3)
    return CollectionColorCard(
        color: .green,
        selection: selection,
        updateSelection: { _, _ in }
    )
    .padding()
    .frame(maxWidth: 360)
    .potatoBackground()
}

#Preview("Color Card – Locked") {
    CollectionColorCard(
        color: .purple,
        selection: nil,
        updateSelection: { _, _ in }
    )
    .padding()
    .frame(maxWidth: 360)
    .potatoBackground()
}
