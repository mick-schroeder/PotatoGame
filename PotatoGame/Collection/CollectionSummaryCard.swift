// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI

struct CollectionSummaryCard: View {
    let unlocked: Int
    let total: Int

    @Environment(\.colorScheme) private var colorScheme

    private var hasAllSchmojis: Bool {
        total > 0 && unlocked >= total
    }

    var body: some View {
        Group {
            if hasAllSchmojis {
                summaryCard(alignment: .center, spacing: 16) {
                    Image("Potato Game Trophy")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 100)
                        .accessibilityHidden(true)

                    Text(.collectionSummaryCompleteTitle)
                        .font(.title3.weight(.semibold))

                    Text(.collectionSummaryCompleteMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)

                    Text(.collectionSummaryUnlockedCount(unlocked, total))
                        .font(.footnote.monospacedDigit())
                }
            } else {
                summaryCard {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(PotatoTheme.cardSecondaryText)
                        .accessibilityHidden(true)

                    Text(.collectionSummaryTitle)
                        .font(.title2.weight(.bold))

                    Text(.collectionSummaryUnlockedCount(unlocked, total))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    

                    ProgressView(
                        value: Double(unlocked),
                        total: max(Double(total), 1)
                    ) {
                        Text(.collectionSummaryProgressLabel)
                            .font(.footnote.weight(.semibold))
                    } currentValueLabel: {
                        Text(Double(unlocked) / max(Double(total), 1), format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                    }
                    .progressViewStyle(.linear)
                    
                    Text(String(localized: "how_to.collection.body"))

                }
            }
        }
    }
}

private extension CollectionSummaryCard {
    func summaryCard(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: alignment, spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .potatoCardStyle(cornerRadius: 28)
    }
}

#Preview("Summary – In Progress") {
    CollectionSummaryCard(unlocked: 18, total: 64)
        .padding()
        .frame(maxWidth: 360)
        .background(Color.gray.opacity(0.1))
}

#Preview("Summary – Complete") {
    CollectionSummaryCard(unlocked: 64, total: 64)
        .padding()
        .frame(maxWidth: 360)
        .background(Color.gray.opacity(0.1))
}
