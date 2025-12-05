// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import CoreGraphics
import Foundation
#if os(iOS)
    import UIKit
#else
    // Stub types so call sites compile on non-iOS platforms.
    enum UIImpactFeedbackGenerator {
        enum FeedbackStyle { case light, medium, heavy, soft, rigid }
    }

    enum UINotificationFeedbackGenerator {
        enum FeedbackType { case success, warning, error }
    }
#endif

enum HapticsCoordinator {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, intensity: CGFloat? = nil, enabled: Bool) {
        #if os(iOS)
            guard enabled else { return }
            Task { @MainActor in
                let generator = UIImpactFeedbackGenerator(style: style)
                generator.prepare()
                if let intensity {
                    generator.impactOccurred(intensity: max(0, min(1, intensity)))
                } else {
                    generator.impactOccurred()
                }
            }
        #else
            _ = (style, intensity, enabled)
        #endif
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType, enabled: Bool) {
        #if os(iOS)
            guard enabled else { return }
            Task { @MainActor in
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(type)
            }
        #else
            _ = (type, enabled)
        #endif
    }
}
