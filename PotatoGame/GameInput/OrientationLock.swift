// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import UIKit

    /// Manages the app's orientation mask using the shared UIWindowScene.
    @MainActor
    final class OrientationLock {
        static let shared = OrientationLock()

        private(set) var currentMask: UIInterfaceOrientationMask = .all

        private init() {}

        func lock(to mask: UIInterfaceOrientationMask) {
            update(mask)
        }

        func restoreSystemDefault() {
            update(.all)
        }

        private func update(_ mask: UIInterfaceOrientationMask) {
            guard currentMask != mask else { return }

            let activeScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

            guard let windowScene = activeScene else { return }
            currentMask = mask
            let preferences = UIWindowScene.GeometryPreferences.iOS()
            preferences.interfaceOrientations = mask
            windowScene.requestGeometryUpdate(preferences) { error in
                print("Failed to update interface orientation: \(error.localizedDescription)")
            }

            // Nudge the current host controller so UIKit reevaluates supported orientations immediately.
            windowScene.windows.first(where: { $0.isKeyWindow })?
                .rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
#endif
