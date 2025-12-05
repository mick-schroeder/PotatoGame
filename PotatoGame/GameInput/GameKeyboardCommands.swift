// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Observation
import SwiftUI

struct GameKeyboardCommands: Commands {
    @Bindable private var keyboardSettings: GameKeyboardSettings

    init(keyboardSettings: GameKeyboardSettings) {
        _keyboardSettings = Bindable(wrappedValue: keyboardSettings)
    }

    var body: some Commands {
        CommandMenu("Gameplay Controls") {
            ForEach(GameInputAction.allCases) { action in
                commandButton(for: action)
            }
        }
    }

    @ViewBuilder
    private func commandButton(for action: GameInputAction) -> some View {
        let shortcut = keyboardSettings.binding(for: action)
        if let keyboardShortcut = shortcut.keyboardShortcut() {
            Button(action.title) {
                GameInputActionDispatcher.send(action)
            }
            .keyboardShortcut(keyboardShortcut)
        } else {
            Button(action.title) {
                GameInputActionDispatcher.send(action)
            }
        }
    }
}
