// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Observation
import SwiftUI

/// Shared navigation coordinator so views do not manipulate `NavigationPath` directly.
@Observable
final class AppRouter {
    var path = NavigationPath()

    var isAtRoot: Bool { path.isEmpty }
    var hasDestinations: Bool { path.isEmpty == false }

    func navigate(to screen: AppScreen) {
        path.append(screen)
    }

    func navigate(to level: PotatoGameLevelInfo) {
        path.append(level)
    }

    func pop() {
        guard hasDestinations else { return }
        path.removeLast()
    }

    func popToRoot() {
        guard hasDestinations else { return }
        path = NavigationPath()
    }
}

// MARK: - Environment support

private struct AppRouterKey: EnvironmentKey {
    static let defaultValue = AppRouter()
}

extension EnvironmentValues {
    var router: AppRouter {
        get { self[AppRouterKey.self] }
        set { self[AppRouterKey.self] = newValue }
    }
}

extension AppRouter: @unchecked Sendable {}
