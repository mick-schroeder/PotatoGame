// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import UIKit

    /// Manages the app's orientation mask using the shared UIWindowScene.
    @MainActor
    final class OrientationLock {
        static let shared = OrientationLock()

        private var currentMask: UIInterfaceOrientationMask = .all

        private init() {}

        func lock(to mask: UIInterfaceOrientationMask) {
            update(mask)
        }

        func restoreSystemDefault() {
            update(.all)
        }

        private func update(_ mask: UIInterfaceOrientationMask) {
            guard currentMask != mask else { return }
            currentMask = mask

            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let preferences = UIWindowScene.GeometryPreferences.iOS()
            preferences.interfaceOrientations = mask
            windowScene.requestGeometryUpdate(preferences) { error in
                print("Failed to update interface orientation: \(error.localizedDescription)")
            }
        }
    }
#endif
