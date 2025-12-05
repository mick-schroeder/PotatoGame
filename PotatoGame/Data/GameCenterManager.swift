// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import Foundation
    import GameKit
    import UIKit

    @MainActor
    class GameCenterManager: NSObject, ObservableObject, @MainActor GKGameCenterControllerDelegate {
        static let shared = GameCenterManager()
        @Published var isAuthenticated = false
        private var didConfigureAuthenticationHandler = false
        private struct ProgressSnapshot: Equatable {
            let levelsCompleted: Int
            let potatoesCreated: Int
            let schmojisUnlocked: Int
            let totalSchmojis: Int
        }

        private var lastReportedProgress: ProgressSnapshot?
        override private init() {
            super.init()
            configureAccessPointVisibility(isEnabled: false)
        }

        func authenticatePlayer() {
            let player = GKLocalPlayer.local
            if didConfigureAuthenticationHandler, player.isAuthenticated {
                DispatchQueue.main.async { [weak self] in
                    self?.isAuthenticated = true
                }
                return
            }

            didConfigureAuthenticationHandler = true
            player.authenticateHandler = { [weak self] vc, error in
                if let vc {
                    // Show the Game Center login UI
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = windowScene.keyWindow?.rootViewController
                    {
                        root.present(vc, animated: true)
                    }
                } else if player.isAuthenticated {
                    DispatchQueue.main.async {
                        self?.isAuthenticated = true
                        self?.lastReportedProgress = nil
                    }
                } else {
                    print("Game Center authentication failed: \(error?.localizedDescription ?? "Unknown error")")
                    DispatchQueue.main.async {
                        self?.isAuthenticated = false
                        self?.lastReportedProgress = nil
                        self?.configureAccessPointVisibility(isEnabled: false)
                    }
                }
            }
        }

        func authenticatePlayerIfNeeded() {
            let player = GKLocalPlayer.local
            if player.isAuthenticated {
                DispatchQueue.main.async {
                    self.isAuthenticated = true
                }
            } else {
                authenticatePlayer()
            }
        }

        func configureAccessPointVisibility(isEnabled: Bool) {
            #if os(iOS)
                let shouldShow = isEnabled && GKLocalPlayer.local.isAuthenticated
                DispatchQueue.main.async {
                    GKAccessPoint.shared.location = .topLeading
                    GKAccessPoint.shared.isActive = shouldShow
                }
            #endif
        }

        func showLeaderboard() {
            let viewController = GKGameCenterViewController(leaderboardID: "potatogame_leaderboard", playerScope: .global, timeScope: .allTime)
            viewController.gameCenterDelegate = self

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = windowScene.keyWindow?.rootViewController
            {
                root.present(viewController, animated: true, completion: nil)
            }
        }

        func loadAchievements(completion: @escaping @Sendable ([GKAchievement]?) -> Void) {
            GKAchievement.loadAchievements { achievements, error in
                if let error {
                    print("Error loading achievements: \(error.localizedDescription)")
                    completion(nil)
                } else {
                    completion(achievements)
                }
            }
        }

        // MARK: - Achievement Sync

        private enum AchievementConstants {
            static let firstGamePlayedID = "grp.FirstGamePlayed"
            static let levelsCompletedID = "grp.levels_completed"
            static let potatoesCreatedID = "grp.potatoes_created"
            static let schmojiCollectedID = "grp.schmoji_collected"
            static let totalLevels = LevelTemplates.map(\.levelNumber).max() ?? 0
            static let totalPotatoes = LevelTemplates.map(\.potentialPotatoCount).reduce(0, +)
        }

        func syncLifetimeProgress(levelsCompleted: Int, potatoesCreated: Int, schmojisUnlocked: Int, totalSchmojis: Int) {
            guard GKLocalPlayer.local.isAuthenticated else { return }

            let snapshot = ProgressSnapshot(
                levelsCompleted: levelsCompleted,
                potatoesCreated: potatoesCreated,
                schmojisUnlocked: schmojisUnlocked,
                totalSchmojis: totalSchmojis
            )

            if snapshot == lastReportedProgress {
                return
            }

            var achievements: [GKAchievement] = []

            if let levelsAchievement = makeProgressAchievement(
                identifier: AchievementConstants.levelsCompletedID,
                completed: levelsCompleted,
                total: AchievementConstants.totalLevels
            ) {
                achievements.append(levelsAchievement)
            }

            if let potatoAchievement = makeProgressAchievement(
                identifier: AchievementConstants.potatoesCreatedID,
                completed: potatoesCreated,
                total: AchievementConstants.totalPotatoes
            ) {
                achievements.append(potatoAchievement)
            }

            if levelsCompleted > 0 || potatoesCreated > 0 {
                let firstGame = GKAchievement(identifier: AchievementConstants.firstGamePlayedID)
                firstGame.percentComplete = 100
                firstGame.showsCompletionBanner = true
                achievements.append(firstGame)
            }

            if let collectionAchievement = makeProgressAchievement(
                identifier: AchievementConstants.schmojiCollectedID,
                completed: schmojisUnlocked,
                total: totalSchmojis
            ) {
                achievements.append(collectionAchievement)
            }

            reportAchievements(achievements, progressSnapshot: snapshot)
        }

        private func makeProgressAchievement(identifier: String, completed: Int, total: Int) -> GKAchievement? {
            guard total > 0 else { return nil }
            let clampedCompleted = max(0, min(completed, total))
            let percent = Double(clampedCompleted) / Double(total) * 100
            let achievement = GKAchievement(identifier: identifier)
            achievement.percentComplete = percent
            achievement.showsCompletionBanner = true
            return achievement
        }

        private func reportAchievements(_ achievements: [GKAchievement], progressSnapshot: ProgressSnapshot) {
            guard GKLocalPlayer.local.isAuthenticated, achievements.isEmpty == false else { return }
            GKAchievement.report(achievements) { [weak self] error in
                if let error {
                    print("Error saving achievements: \(error.localizedDescription)")
                } else {
                    Task { @MainActor in
                        self?.lastReportedProgress = progressSnapshot
                    }
                }
            }
        }

        // MARK: - GKGameCenterControllerDelegate

        func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
            gameCenterViewController.dismiss(animated: true)
        }
    }

#endif
