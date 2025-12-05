// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct KeyboardBindingCaptureView: View {
    let action: GameInputAction
    var onCapture: (GameKeyShortcut) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(action.title)
                    .font(.title2.bold())
                Text("Press the new key or key combination you want to use for this action.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.body)
            }

            KeyCaptureSurface(onCapture: onCapture, onCancel: onCancel)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)

            Button(role: .cancel, action: onCancel) {
                Text("Cancel")
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}

private struct KeyCaptureSurface: View {
    var onCapture: (GameKeyShortcut) -> Void
    var onCancel: () -> Void

    var body: some View {
        Representable(onCapture: onCapture, onCancel: onCancel)
    }

    #if os(macOS)
        struct Representable: NSViewRepresentable {
            var onCapture: (GameKeyShortcut) -> Void
            var onCancel: () -> Void

            func makeNSView(context _: Context) -> KeyCaptureNSView {
                KeyCaptureNSView(onCapture: onCapture, onCancel: onCancel)
            }

            func updateNSView(_: KeyCaptureNSView, context _: Context) {}
        }

        final class KeyCaptureNSView: NSView {
            private let onCapture: (GameKeyShortcut) -> Void
            private let onCancel: () -> Void

            init(onCapture: @escaping (GameKeyShortcut) -> Void, onCancel: @escaping () -> Void) {
                self.onCapture = onCapture
                self.onCancel = onCancel
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override var acceptsFirstResponder: Bool {
                true
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                window?.makeFirstResponder(self)
            }

            override func keyDown(with event: NSEvent) {
                guard let shortcut = GameKeyShortcut(event: event) else {
                    super.keyDown(with: event)
                    return
                }
                onCapture(shortcut)
            }

            override func cancelOperation(_: Any?) {
                onCancel()
            }
        }
    #else
        struct Representable: UIViewRepresentable {
            var onCapture: (GameKeyShortcut) -> Void
            var onCancel: () -> Void

            func makeUIView(context _: Context) -> KeyCaptureUIView {
                KeyCaptureUIView(onCapture: onCapture, onCancel: onCancel)
            }

            func updateUIView(_: KeyCaptureUIView, context _: Context) {}
        }

        final class KeyCaptureUIView: UIView {
            private let onCapture: (GameKeyShortcut) -> Void
            private let onCancel: () -> Void

            init(onCapture: @escaping (GameKeyShortcut) -> Void, onCancel: @escaping () -> Void) {
                self.onCapture = onCapture
                self.onCancel = onCancel
                super.init(frame: .zero)
                backgroundColor = .clear
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override var canBecomeFirstResponder: Bool {
                true
            }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                becomeFirstResponder()
            }

            override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
                guard let press = presses.first, let shortcut = GameKeyShortcut(press: press) else {
                    super.pressesBegan(presses, with: event)
                    return
                }
                onCapture(shortcut)
            }

            override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
                super.pressesCancelled(presses, with: event)
                onCancel()
            }
        }
    #endif
}
