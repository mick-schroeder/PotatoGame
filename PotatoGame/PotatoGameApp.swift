// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftData
import SwiftUI

@main
struct PotatoGameApp: App {
    private let container = SchmojiModelContainerProvider.shared.container
    @State private var keyboardSettings = GameKeyboardSettings()
    @State private var router = AppRouter()
    #if os(iOS)
        @UIApplicationDelegateAdaptor(PotatoGameAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(keyboardSettings)
                .environment(\.router, router)
                .tint(PotatoTheme.accent)
            #if os(macOS)
                .frame(minWidth: 520)
            #endif
        }
        .defaultSize(width: 600, height: 800)
        .commands {
            GameKeyboardCommands(keyboardSettings: keyboardSettings)
        }
    }
}

#if os(iOS)
    final class PotatoGameAppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _: UIApplication,
            supportedInterfaceOrientationsFor _: UIWindow?
        ) -> UIInterfaceOrientationMask {
            OrientationLock.shared.currentMask
        }
    }
#endif
