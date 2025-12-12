import StoreKit
import SwiftUI

struct StoreView: View {
    @Environment(LevelPackStore.self) private var levelPackStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                StoreHeader(isLoading: levelPackStore.isLoading)

                VStack(spacing: 16) {
                    ForEach(LevelPackRegistry.availablePacks) { pack in
                        LevelPackProductCard(pack: pack)
                    }
                }

                RestorePurchasesButton()
                    .padding()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: CGFloat(PotatoGameOptions.width))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .potatoBackground()
        .navigationTitle(Text(.linksLevelStore))
        .alert(
            Text(LocalizedStringResource("levels.level-pack.error.title", defaultValue: "Level Pack Error")),
            isPresented: purchaseErrorBinding,
            presenting: levelPackStore.purchaseError
        ) { _ in
            Button(role: .cancel) {
                levelPackStore.purchaseError = nil
            } label: {
                Text(.buttonOk)
            }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var purchaseErrorBinding: Binding<Bool> {
        Binding(
            get: { levelPackStore.purchaseError != nil },
            set: { newValue in
                if newValue == false {
                    levelPackStore.purchaseError = nil
                }
            }
        )
    }
}

private struct StoreHeader: View {
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(PotatoTheme.cardSecondaryText)
                .accessibilityHidden(true)

            Text(LocalizedStringResource("store.header.title", defaultValue: "Level Pack Store"))
                .font(.title2.weight(.bold))

            Text(
                LocalizedStringResource(
                    "store.header.subtitle",
                    defaultValue: "Purchase extra level packs to access even more potato puzzles."
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .potatoCardStyle(cornerRadius: 32)
    }
}

private struct LevelPackProductCard: View {
    let pack: LevelPackDefinition
    @Environment(LevelPackStore.self) private var levelPackStore
    @AppStorage("haptics") private var hapticsEnabled: Bool = PotatoGameOptions.haptics

    private var isUnlocked: Bool {
        levelPackStore.purchasedPackIDs.contains(pack.id)
    }

    private var priceText: String {
        if let product = levelPackStore.product(for: pack) {
            return product.displayPrice
        }
        return String(localized: LocalizedStringResource("store.pack.loadingPrice", defaultValue: "Loading price…"))
    }

    private var levelRangeText: String {
        let lower = pack.levelRange.lowerBound.formatted()
        let upper = pack.levelRange.upperBound.formatted()
        return "Levels \(lower) – \(upper)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(pack.displayName)
                    .font(.headline)

                Spacer()

                if isUnlocked {
                    Label {
                        Text(LocalizedStringResource("store.pack.unlocked", defaultValue: "Unlocked"))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                }
            }

            Text(levelRangeText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if isUnlocked == false {
                Button(action: purchasePack) {
                    HStack(spacing: 8) {
                        if levelPackStore.purchaseInProgress {
                            ProgressView()
                                .controlSize(.small)
                            Text(LocalizedStringResource("store.pack.purchasing", defaultValue: "Purchasing…"))
                                .fontWeight(.semibold)
                        } else {
                            Text(priceText)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                }
                .glassButtonStyle(prominent: true)
                .disabled(levelPackStore.purchaseInProgress || levelPackStore.isLoading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .potatoCardStyle(cornerRadius: 26)
    }

    private func purchasePack() {
        HapticsCoordinator.impact(.rigid, enabled: hapticsEnabled)
        Task {
            await levelPackStore.purchase(pack: pack)
        }
    }
}

private struct RestorePurchasesButton: View {
    @Environment(LevelPackStore.self) private var levelPackStore
    @AppStorage("haptics") private var hapticsEnabled: Bool = PotatoGameOptions.haptics

    var body: some View {
        Button(action: restorePurchases) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                Text(LocalizedStringResource("store.restorePurchases", defaultValue: "Restore Purchases"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(6)
        }
        .glassButtonStyle(prominent: false)
        .tint(PotatoTheme.button)
        .disabled(levelPackStore.isLoading || levelPackStore.purchaseInProgress)
    }

    private func restorePurchases() {
        HapticsCoordinator.notification(.warning, enabled: hapticsEnabled)
        Task {
            await levelPackStore.restorePurchases()
        }
    }
}

#Preview {
    NavigationStack {
        StoreView()
            .environment(PreviewSampleData.makeLevelPackStore())
    }
}
