// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import GameKit
import SpriteKit
import SwiftData
import SwiftUI

/// The main view of the app, displaying navigation links and Game Center integration.
struct ContentView: View {
    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.router) private var appRouter

    @Query private var accounts: [Account]

    @State private var pendingNewGameReset = false
    @State private var isResettingGame = false

    @State private var levelPackStore = LevelPackStore()

    #if os(macOS)
        @FocusState private var isPlayFocused: Bool
    #endif

    // MARK: - Game Center

    @AppStorage("gamecenter") var gameCenter: Bool = SchmojiOptions.gameCenter
    @AppStorage("haptics") private var hapticsEnabled: Bool = SchmojiOptions.haptics

    #if os(iOS)
        @StateObject private var gameCenterManager = GameCenterManager.shared
    #endif

    // MARK: - View Body

    var body: some View {
        @Bindable var router = appRouter

        NavigationStack(path: $router.path) {
            homeView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentMargins(20, for: .scrollContent)
                .background(backgroundLayer)
                .potatoNavigationDestinations()
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            router.navigate(to: .settings)
                        } label: {
                            Image(systemName: "gear")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(Text(.buttonSettings))
                    }
                }
            #if os(macOS)
                .defaultFocus($isPlayFocused, true)
            #endif
        }
        .environment(levelPackStore)
        .onReceive(NotificationCenter.default.publisher(for: .newGameRequested)) { _ in
            Task { @MainActor in
                newGame()
            }
        }
        .onChange(of: appRouter.path) { _, newPath in
            if pendingNewGameReset, newPath.isEmpty {
                completeNewGameReset()
            }
            #if os(iOS)
                updateAccessPointVisibility()
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            #if os(iOS)
                if newPhase == .active, gameCenter {
                    gameCenterManager.authenticatePlayerIfNeeded()
                }
            #endif
        }
        #if os(iOS)
        .onAppear {
            if gameCenter {
                gameCenterManager.authenticatePlayerIfNeeded()
            }
            updateAccessPointVisibility()
        }
        .onChange(of: gameCenter) { _, newValue in
            if newValue {
                gameCenterManager.authenticatePlayerIfNeeded()
            }
            updateAccessPointVisibility()
        }
        .onChange(of: gameCenterManager.isAuthenticated) { _, _ in
            updateAccessPointVisibility()
        }
        .onDisappear {
            gameCenterManager.configureAccessPointVisibility(isEnabled: false)
        }
        #endif
        .task(id: accounts.first?.id) {
            levelPackStore.configure(with: modelContext, account: accounts.first)
        }
    }

    private var homeView: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    homeCard
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
        }
    }

    private var homeCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroHeader
            potatoCountSection
            SchmojiColorsLegendGenericView()
                .foregroundStyle(PotatoTheme.secondaryText)
            playButton
            LinksView()
        }
        .padding()
        .frame(maxWidth: 400)
        .glassedCard(cornerRadius: 30, interactive: true)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Link(destination: URL(string: "https://mickschroeder.com")!) {
                Text(.developerHeroLink)
            }
            .font(.title2.bold())
            .foregroundStyle(PotatoTheme.secondaryText)
            #if os(iOS)
                .hoverEffect(.highlight)
            #endif
            #if os(macOS)
            .focusable(false)
            #endif
            Text(.appName)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(PotatoTheme.titleText)
        }
        .padding(.top)
    }

    private var potatoCountSection: some View {
        HStack {
            Spacer()
            PotatoCountView()
            Spacer()
        }
    }

    private var playButton: some View {
        Button {
            HapticsCoordinator.impact(.heavy, enabled: hapticsEnabled)
            appRouter.navigate(to: .game)
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
        .frame(minHeight: 38)
        .accessibilityLabel(Text(.accessibilityHomePlayNext))
        #if os(macOS)
            .focused($isPlayFocused)
        #endif
    }

    private var backgroundLayer: some View {
        ZStack {
            PotatoTankView()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @MainActor
    private func newGame() {
        guard isResettingGame == false else { return }
        isResettingGame = true
        pendingNewGameReset = true
        let hadActiveDestinations = appRouter.hasDestinations
        appRouter.popToRoot()
        #if os(iOS)
            gameCenterManager.configureAccessPointVisibility(isEnabled: false)
        #endif
        if hadActiveDestinations == false {
            completeNewGameReset()
        }
    }

    @MainActor
    private func completeNewGameReset() {
        guard pendingNewGameReset else { return }
        DataGeneration.startNewGame(modelContext: modelContext)
        pendingNewGameReset = false
        isResettingGame = false
        #if os(iOS)
            updateAccessPointVisibility()
        #endif
    }
}

#if os(iOS)
    private extension ContentView {
        func updateAccessPointVisibility() {
            let shouldEnable = appRouter.isAtRoot && gameCenter && gameCenterManager.isAuthenticated
            gameCenterManager.configureAccessPointVisibility(isEnabled: shouldEnable)
        }
    }
#endif

#Preview("Home") {
    ContentView()
        .environment(PreviewSampleData.makeLevelPackStore())
        .environment(GameKeyboardSettings())
        .modelContainer(PreviewSampleData.makeContainer())
}
