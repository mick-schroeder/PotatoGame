// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif
import SpriteKit
import SwiftData
import SwiftUI

/// SwiftUI wrapper that hosts the SpriteKit scene and in-game HUD.
@MainActor
struct PotatoGameView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismissView
    @Environment(LevelPackStore.self) private var levelPackStore
    @Environment(GameKeyboardSettings.self) private var keyboardSettings

    @AppStorage("showLegend") private var legendVisible: Bool = PotatoGameOptions.showLegend
    @AppStorage("sound") private var soundEnabled: Bool = PotatoGameOptions.sound
    @AppStorage("haptics") private var hapticsEnabled: Bool = PotatoGameOptions.haptics
    @AppStorage("mergeTutorialSeen") private var mergeTutorialSeen: Bool = false
    @AppStorage("mergeTutorialAccountJoinDate") private var mergeTutorialAccountJoinDate: TimeInterval = 0

    @State private var viewModel: PotatoGameSessionViewModel
    @State private var isSeedingAccount = false
    @State private var howToPlayVisible = false
    @State private var mergeTutorialVisible = false
    @State private var wasPausedBeforeTutorial = false
    #if os(iOS)
        @State private var didApplyOrientationLock = false
    #endif

    #if DEBUG
        @State private var debugMatchOverlayEnabled = false
    #endif

    @Query private var accounts: [Account]
    @Query private var selections: [EmojiSelection]
    @Query(sort: [SortDescriptor(\PotatoGameLevelProgress.levelNumber, order: .forward)]) private var levelProgress: [PotatoGameLevelProgress]

    @ScaledMetric(relativeTo: .title) private var headerIconSize: CGFloat = 32

    private var levelTint: Color {
        viewModel.level?.levelBackgroundColor.color ?? Color("PotatoSecondaryBackground")
    }

    private var sessionInputSignature: SessionInputSignature {
        SessionInputSignature(
            progress: levelProgress,
            accounts: accounts,
            selections: selections,
            purchasedPackIDs: levelPackStore.purchasedPackIDs,
            soundEnabled: soundEnabled,
            hapticsEnabled: hapticsEnabled,
            colorScheme: colorScheme
        )
    }

    init(level: PotatoGameLevelInfo? = nil) {
        _viewModel = State(initialValue: PotatoGameSessionViewModel(initialLevel: level))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        rootContent()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    gameMenu
                }
            }
            .navigationTitle(Text(.appName))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .onAppear {
                #if DEBUG
                    applyDebugOverlayState()
                #endif
                #if os(iOS)
                    OrientationLock.shared.lock(to: .portrait)
                    didApplyOrientationLock = true
                #endif
            }
            .task(id: sessionInputSignature) {
                ensureAccountAvailable()
                viewModel.updateData(
                    modelContext: modelContext,
                    colorScheme: colorScheme,
                    soundEnabled: soundEnabled,
                    hapticsEnabled: hapticsEnabled,
                    accounts: accounts,
                    selections: selections,
                    levelProgress: levelProgress,
                    purchasedPackIDs: levelPackStore.purchasedPackIDs,
                    keyboardSettings: keyboardSettings
                )
                presentMergeTutorialIfNeeded()
            }
            .onDisappear {
                viewModel.persistSessionState()
                viewModel.stopAutosaveLoop()
                #if os(iOS)
                    if didApplyOrientationLock {
                        OrientationLock.shared.restoreSystemDefault()
                        didApplyOrientationLock = false
                    }
                #endif
            }

            .onChange(of: mergeTutorialVisible) { _, isVisible in
                viewModel.withSession { _, scene in
                    if isVisible {
                        wasPausedBeforeTutorial = scene.isPaused
                        scene.isPaused = true
                    } else {
                        scene.isPaused = wasPausedBeforeTutorial
                    }
                }
            }

        #if DEBUG
            .onChange(of: debugMatchOverlayEnabled) { _, _ in
                applyDebugOverlayState()
            }
        #endif
            .sheet(item: $viewModel.presentedGameSheet, onDismiss: viewModel.handleGameSheetDismissal) { sheet in
                gameEndSheet(for: sheet)
            }
            .sheet(isPresented: $howToPlayVisible) {
                NavigationStack {
                    HowToPlayView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    howToPlayVisible = false
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
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }

    /// Main content stack: header + SpriteKit board over gradient background.
    @ViewBuilder
    private func rootContent() -> some View {
        ZStack {
            backgroundView

            VStack {
                headerCard
                gameBoard
            }
            .padding(.horizontal)
            #if os(macOS)
                .padding(.vertical)
            #endif

                .frame(maxWidth: CGFloat(PotatoGameOptions.width), alignment: .center)

            if mergeTutorialVisible {
                mergeTutorialOverlay
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
            }
        }
    }
}

// MARK: - Subviews

@MainActor private extension PotatoGameView {
    /// Overflow menu for pause/restart/settings/debug actions.
    @ViewBuilder
    private var gameMenu: some View {
        Menu {
            Button {
                viewModel.togglePause()
            } label: {
                let title: LocalizedStringResource = viewModel.isPaused ? .buttonResume : .buttonPause
                let iconName = viewModel.isPaused ? "play.circle" : "pause.circle"
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: iconName)
                }
            }

            Button {
                viewModel.restartLevel()
            } label: {
                Label {
                    Text(.buttonRestartLevel)
                } icon: {
                    Image(systemName: "arrow.counterclockwise.circle")
                }
            }
            #if DEBUG
                Button {
                    viewModel.withSession { manager, scene in
                        manager.handleWin(in: scene)
                    }
                } label: {
                    Label {
                        Text(.buttonWinLevel)
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                }

                Button {
                    viewModel.withSession { manager, scene in
                        manager.handleWin(in: scene, perfect: true)
                    }
                } label: {
                    Label {
                        Text(.buttonPerfectWin)
                    } icon: {
                        Image(systemName: "star.circle.fill")
                    }
                }

                Button {
                    viewModel.withSession { manager, scene in
                        manager.handleLoss(in: scene)
                    }
                } label: {
                    Label {
                        Text(.buttonLoseLevel)
                    } icon: {
                        Image(systemName: "x.circle")
                    }
                }
            #endif
            Button {
                viewModel.withSession { manager, scene in
                    manager.handleEnd(in: scene)
                }
            } label: {
                Label {
                    Text(.buttonEndLevel)
                } icon: {
                    Image(systemName: "flag")
                }
            }
            Divider()
            Toggle(isOn: $soundEnabled) {
                Label {
                    Text(.settingsSound)
                } icon: {
                    Image(systemName: soundEnabled ? "speaker.fill" : "speaker.slash.fill")
                }
            }

            Toggle(isOn: $hapticsEnabled) {
                Label {
                    Text(.settingsHaptics)
                } icon: {
                    Image(systemName: hapticsEnabled ? "apple.haptics.and.music.note" : "apple.haptics.and.music.note.slash")
                }
            }

            Toggle(isOn: $legendVisible) {
                Label {
                    Text(.gameMenuShowLegend)
                } icon: {
                    Image(systemName: legendVisible ? "rectangle" : "rectangle.slash")
                }
            }
            Button {
                howToPlayVisible = true
            } label: {
                Label {
                    Text("navigation.how_to_play")
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
            }
            #if DEBUG
                Toggle(isOn: $debugMatchOverlayEnabled) {
                    Label {
                        Text(.gameMenuDebugMatchOverlay)
                    } icon: {
                        Image(systemName: debugMatchOverlayEnabled ? "viewfinder.circle" : "viewfinder.circle.fill")
                    }
                }
            #endif
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        #if os(macOS)
        .labelStyle(.titleAndIcon)
        #else
        .labelStyle(.titleAndIcon)
        #endif
        .accessibilityLabel(Text(.gameMenuLabel))
    }
}

@MainActor private extension PotatoGameView {
    func ensureAccountAvailable() {
        guard accounts.isEmpty, isSeedingAccount == false else { return }
        isSeedingAccount = true
        Task(priority: .utility) { @MainActor in
            let accountID = await PotatoGameModelContainerProvider.accountID()
            DataGeneration.ensureBaselineData(modelContext: modelContext, userID: accountID)
            isSeedingAccount = false
        }
    }

    /// Keep the first-play merge tutorial tightly scoped to level 1.
    var isLikelyFirstSession: Bool {
        guard let currentLevel = viewModel.level else { return false }
        guard currentLevel.levelNumber == 1 else { return false }
        
        return true
    }

    func presentMergeTutorialIfNeeded() {
        resetMergeTutorialIfAccountChanged()
        guard mergeTutorialVisible == false else { return }
        guard viewModel.level != nil else { return }
        guard isLikelyFirstSession else { return }
        guard mergeTutorialSeen == false else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
            mergeTutorialVisible = true
        }
    }

    func dismissMergeTutorial() {
        mergeTutorialSeen = true
        withAnimation(.easeOut(duration: 0.2)) {
            mergeTutorialVisible = false
        }
    }

    private func resetMergeTutorialIfAccountChanged() {
        guard let joinDate = accounts.first?.joinDate.timeIntervalSince1970 else { return }
        guard mergeTutorialAccountJoinDate != joinDate else { return }
        mergeTutorialAccountJoinDate = joinDate
        mergeTutorialSeen = false
    }

    /// Gradient background matching the current level tint.
    var backgroundView: some View {
        let colors: [Color] = [
            levelTint.opacity(colorScheme == .dark ? 0.9 : 0.75),
            levelTint.opacity(0.45),
            Color.appBackground,
        ]
        return LinearGradient(
            colors: colors,
            startPoint: UnitPoint.topLeading,
            endPoint: UnitPoint.bottomTrailing
        )
        .ignoresSafeArea()
    }

    /// Title card that shows the current level number and potato wallet.
    var headerCard: some View {
        VStack {
            HStack(spacing: 0) {
                Text(viewModel.levelNumberKey)
                    .font(.title3.weight(.bold))
                Spacer(minLength: 12)
                if let potatoCount = accounts.first?.potatoCount {
                    HStack(spacing: 10) {
                        Image("Cool Potato")
                            .resizable()
                            .scaledToFit()
                            .frame(width: headerIconSize, height: headerIconSize)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 3)

                        Text("\(potatoCount)")
                            .font(.title3.weight(.bold))
                    }
                }
            }

            if legendVisible {
                legendOverlay
            }
        }
        .padding()
        .glassedSurface(in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: true)
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 16, x: 0, y: 8)
    }

    /// Renders the SpriteKit scene (or progress indicator while loading).
    var gameBoard: some View {
        // Shared container and modifiers so both branches have the same concrete type
        let boardShape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        let boardAspect = CGSize(width: CGFloat(PotatoGameOptions.width), height: CGFloat(PotatoGameOptions.height))
        return ZStack {
            boardShape
                .fill(Color.clear)
                .glassedSurface(in: boardShape, interactive: true)
                .aspectRatio(boardAspect, contentMode: .fit)

            if let scene = viewModel.scene {
                #if DEBUG
                    let debugOptions: SpriteView.DebugOptions = [.showsFPS]
                #else
                    let debugOptions: SpriteView.DebugOptions = []
                #endif

                SpriteView(scene: scene, options: [], debugOptions: debugOptions)
                    .id(viewModel.level?.id ?? 0)
                    .aspectRatio(boardAspect, contentMode: .fit)
                    .clipShape(boardShape)
                    .overlay {
                        if viewModel.isPaused {
                            pauseOverlay(boardShape: boardShape)
                        }
                    }
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding()
                    .aspectRatio(boardAspect, contentMode: .fit)
                    .clipShape(boardShape)
            }
            boardShape
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.25), lineWidth: 1.2)
                .aspectRatio(boardAspect, contentMode: .fit)
        }
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.22), radius: 30, x: 0, y: 24)
    }

    /// Color legend overlay shown when the user enables “show legend”.
    var legendOverlay: some View {
        PotatoGameLegendView()
            .allowsHitTesting(false)
    }

    /// First-time onboarding overlay that explains the merge mechanic.
    var mergeTutorialOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .opacity(0.75)
            
            VStack(spacing: 20) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.yellow)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("merge_tutorial.title")
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(.primary)

                        Text("merge_tutorial.body")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                PotatoGameLegendView()
               VStack(spacing: 12) {
                    Button {
                        dismissMergeTutorial()
                    } label: {
                        Label {
                            Text("merge_tutorial.cta")
                        } icon: {
                            Image(systemName: "play.fill")
                        }
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        dismissMergeTutorial()
                        howToPlayVisible = true
                    } label: {
                        Label {
                            Text("navigation.how_to_play")
                        } icon: {
                            Image(systemName: "book")
                        }
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 20)
            .frame(maxWidth: 520)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.2), radius: 28, x: 0, y: 18)
            }
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isModal)
        }
    }

    @ViewBuilder
    private func badgePill(systemName: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.09 : 0.14))
        )
        .foregroundStyle(.primary)
    }

    /// Wraps the win/lose view in a helper so we can attach lifecycle hooks.
    private func gameEndSheet(for sheet: GameEndSheet) -> some View {
        PotatoGameEndView(
            level: sheet.level,
            outcome: viewModel.outcome(for: sheet),
            isNextLevelAvailable: sheet.hasNextLevel,
            onReplay: {
                viewModel.restartLevel()
            },
            onNextLevel: {
                viewModel.navigateToNextLevel()
            },
            onQuit: {
                exitToHome()
            }
        )
        .gameEndSheetStyle()
        .onAppear {
            viewModel.markSheetPresented(sheet)
        }
    }

    /// Called when the sheet’s “Quit” button is tapped.
    private func exitToHome() {
        viewModel.prepareForExit()
        dismissView()
    }

    /// Lighthearted pause UI that blurs the board and shows a quip.
    private func pauseOverlay(boardShape: RoundedRectangle) -> some View {
        ZStack {
            boardShape
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.25),
                            Color.black.opacity(0.1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 44, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white.opacity(0.9))

                Text(.buttonPause)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 24)
        }
        .clipShape(boardShape)
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 16)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(.easeInOut(duration: 0.22), value: viewModel.isPaused)
    }

    #if DEBUG
        func applyDebugOverlayState() {
            viewModel.applyDebugMatchOverlay(enabled: debugMatchOverlayEnabled)
        }
    #endif
}

/// Hashable bundle of dependencies that should trigger a session update when changed.
/// We collapse large SwiftData collections down to integer digests to keep `.task(id:)` cheap.
private struct SessionInputSignature: Equatable {
    let progressDigest: Int
    let accountDigest: Int
    let selectionDigest: Int
    let purchasedPackDigest: Int
    let soundEnabled: Bool
    let hapticsEnabled: Bool
    let colorScheme: ColorScheme

    @MainActor
    init(
        progress: [PotatoGameLevelProgress],
        accounts: [Account],
        selections: [EmojiSelection],
        purchasedPackIDs: Set<String>,
        soundEnabled: Bool,
        hapticsEnabled: Bool,
        colorScheme: ColorScheme
    ) {
        progressDigest = Self.digestProgress(progress)
        accountDigest = Self.digestAccounts(accounts)
        selectionDigest = Self.digestSelections(selections)
        purchasedPackDigest = Self.digestPurchasedPackIDs(purchasedPackIDs)
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.colorScheme = colorScheme
    }

    @MainActor
    private static func digestProgress(_ entries: [PotatoGameLevelProgress]) -> Int {
        var hasher = Hasher()
        hasher.combine(entries.count)
        for entry in entries {
            hasher.combine(entry.levelNumber)
            hasher.combine(entry.gameState)
            hasher.combine(entry.numOfPotatoesCreated)
        }
        return hasher.finalize()
    }

    @MainActor
    private static func digestAccounts(_ accounts: [Account]) -> Int {
        var hasher = Hasher()
        let ordered = accounts.sorted { $0.id < $1.id }
        hasher.combine(ordered.count)
        for account in ordered {
            hasher.combine(account.id)
            hasher.combine(account.potatoCount)
            hasher.combine(account.purchasedLevelPackIDs.sorted())
        }
        return hasher.finalize()
    }

    @MainActor
    private static func digestSelections(_ selections: [EmojiSelection]) -> Int {
        var hasher = Hasher()
        let ordered = selections.sorted { $0.colorRawValue < $1.colorRawValue }
        hasher.combine(ordered.count)
        for selection in ordered {
            hasher.combine(selection.colorRawValue)
            hasher.combine(selection.selectedHex)
            hasher.combine(selection.unlockedHexes.count)
            hasher.combine(selection.perfectWinCount)
        }
        return hasher.finalize()
    }

    private static func digestPurchasedPackIDs(_ ids: Set<String>) -> Int {
        var hasher = Hasher()
        let ordered = ids.sorted()
        hasher.combine(ordered.count)
        ordered.forEach { hasher.combine($0) }
        return hasher.finalize()
    }
}

/// Lightweight model describing which sheet variant to show.
struct GameEndSheet: Identifiable, Equatable {
    enum Kind {
        case win
        case lose
    }

    var id: String {
        "\(level.id)-\(kind)-\(resumeOnDismiss)"
    }

    let kind: Kind
    let level: PotatoGameLevelInfo
    let unlockProgress: EmojiSelection.UnlockProgress?
    let hasNextLevel: Bool
    let resumeOnDismiss: Bool
}

private extension View {
    @ViewBuilder
    func gameEndSheetStyle() -> some View {
        #if os(iOS)
            presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        #elseif os(macOS)
            if #available(macOS 15.0, *) {
                self
                    .frame(minWidth: 420)
                    .presentationSizing(.fitted)
            } else {
                frame(minWidth: 420)
            }
        #else
            self
        #endif
    }
}

#Preview("Potato Game View") {
    NavigationStack {
        PotatoGameView()
    }
    .environment(PreviewSampleData.makeLevelPackStore())
    .environment(GameKeyboardSettings())
    .modelContainer(PreviewSampleData.makeContainer())
}
