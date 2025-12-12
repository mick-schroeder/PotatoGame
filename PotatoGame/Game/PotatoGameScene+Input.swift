// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

#if os(iOS)
    import CoreMotion
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif
import Foundation
import GameController
import SpriteKit

/// Handles touch, keyboard, and controller input for the SpriteKit scene.
@MainActor
extension PotatoGameScene {
    #if os(iOS)
        override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            handleSelection(at: location)
        }
    #endif

    /// Maps high-level input actions to their selection handlers.
    private func handleKeyboardAction(_ action: GameInputAction) {
        switch action {
        case .nextCluster:
            selectNextMatchCluster()
        case .confirmCluster:
            confirmCurrentSelection()
        case .clearSelection:
            clearSchmojiSelection()
        }
    }

    /// Receives NotificationCenter events from macOS/iPad keyboard shortcuts.
    @objc func handleExternalKeyboardAction(_ notification: Notification) {
        guard let action = notification.object as? GameInputAction else { return }
        handleKeyboardAction(action)
    }

    #if os(macOS)
        override func mouseDown(with event: NSEvent) {
            let location = event.location(in: self)
            handleSelection(at: location)
        }
    #endif

    // MARK: - Game Controller

    /// Central place where every input surface feeds device gravity overrides.
    func updateGravity(dx: CGFloat, dy: CGFloat) {
        physicsWorld.gravity = CGVector(dx: dx, dy: dy)
    }

    private func restoreDefaultGravityIfNeeded() {
        #if os(iOS)
            let motionActive = motionManager.isDeviceMotionActive
        #else
            let motionActive = false
        #endif
        guard motionActive == false,
              hasKeyboardGravityOverride == false,
              hasControllerGravityOverride == false
        else { return }
        updateGravity(dx: defaultGravity.dx, dy: defaultGravity.dy)
    }

    private func scaledControllerGravity(_ value: Float) -> CGFloat {
        CGFloat(value) * gravityMagnitude
    }

    private func applyControllerInput(from pad: GCControllerDirectionPad) {
        applyControllerInput(x: pad.xAxis.value, y: -pad.yAxis.value)
    }

    private func applyControllerInput(x: Float, y: Float) {
        let deadzone: Float = 0.02
        if abs(x) < deadzone, abs(y) < deadzone {
            hasControllerGravityOverride = false
            restoreDefaultGravityIfNeeded()
            return
        }

        hasControllerGravityOverride = true
        let gravityX = scaledControllerGravity(x)
        let gravityY = scaledControllerGravity(-y) // Invert Y-axis to match SpriteKit's coordinate system
        updateGravity(dx: gravityX, dy: gravityY)
    }

    /// Registers callbacks the first time a controller is seen so we stop polling each frame.
    func configureControllerIfNeeded(_ controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        guard controllerIdentifiers.insert(identifier).inserted else { return }

        if let motion = controller.motion {
            motion.valueChangedHandler = { [weak self] motion in
                self?.applyControllerInput(x: Float(motion.gravity.x), y: Float(motion.gravity.y))
            }
        }

        if let gamepad = controller.extendedGamepad {
            configureExtendedGamepad(gamepad, for: controller)
        } else if let micro = controller.microGamepad {
            configureMicroGamepad(micro, for: controller)
        }
    }

    private func configureExtendedGamepad(_ gamepad: GCExtendedGamepad, for _: GCController) {
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.applyControllerInput(x: xValue, y: -yValue)
        }
        #if os(iOS)
            gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
                self?.applyControllerInput(x: xValue, y: -yValue)
            }
        #else
            if let rightThumbstick = gamepad.rightThumbstick as GCControllerDirectionPad? {
                rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
                    self?.applyControllerInput(x: xValue, y: -yValue)
                }
            }
        #endif
        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.applyControllerInput(x: xValue, y: -yValue)
        }
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.confirmCurrentSelection()
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.selectNextMatchCluster()
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.clearSchmojiSelection()
        }
    }

    private func configureMicroGamepad(_ gamepad: GCMicroGamepad, for _: GCController) {
        gamepad.reportsAbsoluteDpadValues = true
        gamepad.allowsRotation = true
        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.applyControllerInput(x: xValue, y: -yValue)
        }
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.confirmCurrentSelection()
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.selectNextMatchCluster()
        }
    }

    func registerControllerNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDidConnect(_:)), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDidDisconnect(_:)), name: .GCControllerDidDisconnect, object: nil)
        GCController.controllers().forEach { configureControllerIfNeeded($0) }
    }

    func unregisterControllerNotifications() {
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidDisconnect, object: nil)
        controllerIdentifiers.removeAll()
    }

    @objc private func controllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        configureControllerIfNeeded(controller)
    }

    @objc private func controllerDidDisconnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        teardownController(controller)
        controllerIdentifiers.remove(ObjectIdentifier(controller))
        hasControllerGravityOverride = false
        restoreDefaultGravityIfNeeded()
    }

    private func teardownController(_ controller: GCController) {
        controller.motion?.valueChangedHandler = nil
        controller.extendedGamepad?.leftThumbstick.valueChangedHandler = nil
        controller.extendedGamepad?.rightThumbstick.valueChangedHandler = nil
        controller.extendedGamepad?.dpad.valueChangedHandler = nil
        controller.extendedGamepad?.buttonA.pressedChangedHandler = nil
        controller.extendedGamepad?.buttonB.pressedChangedHandler = nil
        controller.extendedGamepad?.buttonY.pressedChangedHandler = nil
        controller.microGamepad?.dpad.valueChangedHandler = nil
        controller.microGamepad?.buttonA.pressedChangedHandler = nil
        controller.microGamepad?.buttonX.pressedChangedHandler = nil
    }

    #if os(iOS) || os(macOS)
        private func setKeyboardDirection(_ direction: DirectionKey, active: Bool) {
            let changed: Bool = if active {
                activeKeyboardDirections.insert(direction).inserted
            } else {
                activeKeyboardDirections.remove(direction) != nil
            }

            if changed {
                updateKeyboardGravity()
            }
        }

        /// Arrow/WASD input simply substitutes a fake gravity vector until released.
        private func updateKeyboardGravity() {
            let horizontal = (activeKeyboardDirections.contains(.right) ? 1 : 0)
                - (activeKeyboardDirections.contains(.left) ? 1 : 0)
            let vertical = (activeKeyboardDirections.contains(.down) ? 1 : 0)
                - (activeKeyboardDirections.contains(.up) ? 1 : 0)

            if horizontal == 0, vertical == 0 {
                hasKeyboardGravityOverride = false
                restoreDefaultGravityIfNeeded()
            } else {
                hasKeyboardGravityOverride = true
                let gravityX = scaledControllerGravity(Float(horizontal))
                let gravityY = scaledControllerGravity(Float(-vertical))
                updateGravity(dx: gravityX, dy: gravityY)
            }
        }
    #endif

    #if os(macOS)
        override func keyDown(with event: NSEvent) {
            if let action = keyboardAction(for: event) {
                handleKeyboardAction(action)
                return
            }

            if let direction = keyboardDirection(for: event) {
                if event.isARepeat {
                    return
                }
                setKeyboardDirection(direction, active: true)
                return
            }

            super.keyDown(with: event)
        }

        override func keyUp(with event: NSEvent) {
            if keyboardAction(for: event) != nil {
                return
            }

            if let direction = keyboardDirection(for: event) {
                setKeyboardDirection(direction, active: false)
                return
            }

            super.keyUp(with: event)
        }

        private func keyboardDirection(for event: NSEvent) -> DirectionKey? {
            switch event.keyCode {
            case 123, 0:
                .left // Left arrow or A
            case 124, 2:
                .right // Right arrow or D
            case 126, 13:
                .up // Up arrow or W
            case 125, 1:
                .down // Down arrow or S
            default:
                nil
            }
        }

        private func keyboardAction(for event: NSEvent) -> GameInputAction? {
            keyboardSettings?.action(matching: event)
        }
    #endif

    #if os(iOS)
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard isIPadDevice else {
                super.pressesBegan(presses, with: event)
                return
            }
            var handled = false
            for press in presses {
                if let action = keyboardAction(for: press) {
                    handleKeyboardAction(action)
                    handled = true
                    continue
                }
                guard let direction = keyboardDirection(for: press) else { continue }
                setKeyboardDirection(direction, active: true)
                handled = true
            }

            if handled == false {
                super.pressesBegan(presses, with: event)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard isIPadDevice else {
                super.pressesEnded(presses, with: event)
                return
            }
            var handled = false
            for press in presses {
                if keyboardAction(for: press) != nil {
                    handled = true
                    continue
                }
                guard let direction = keyboardDirection(for: press) else { continue }
                setKeyboardDirection(direction, active: false)
                handled = true
            }

            if handled == false {
                super.pressesEnded(presses, with: event)
            }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard isIPadDevice else {
                super.pressesCancelled(presses, with: event)
                return
            }
            pressesEnded(presses, with: event)
        }

        private func keyboardDirection(for press: UIPress) -> DirectionKey? {
            if let key = press.key {
                if #available(iOS 13.4, *),
                   let usage = UIKeyboardHIDUsage(rawValue: key.keyCode.rawValue)
                {
                    switch usage {
                    case .keyboardLeftArrow:
                        return .left
                    case .keyboardRightArrow:
                        return .right
                    case .keyboardUpArrow:
                        return .up
                    case .keyboardDownArrow:
                        return .down
                    default:
                        break
                    }
                }

                let characters = key.charactersIgnoringModifiers.lowercased()
                switch characters {
                case "a":
                    return .left
                case "d":
                    return .right
                case "w":
                    return .up
                case "s":
                    return .down
                default:
                    break
                }
            }

            switch press.type {
            case .upArrow:
                return .up
            case .downArrow:
                return .down
            case .leftArrow:
                return .left
            case .rightArrow:
                return .right
            default:
                return nil
            }
        }

        private func keyboardAction(for press: UIPress) -> GameInputAction? {
            keyboardSettings?.action(matching: press)
        }
    #endif

    #if os(iOS)
        func configureHardwareKeyboard() {
            guard isIPadDevice, #available(iOS 14.0, *) else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(hardwareKeyboardDidConnect(_:)), name: .GCKeyboardDidConnect, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(hardwareKeyboardDidDisconnect(_:)), name: .GCKeyboardDidDisconnect, object: nil)
            if let keyboard = GCKeyboard.coalesced {
                bindHardwareKeyboard(keyboard)
            }
        }

        func teardownHardwareKeyboard() {
            guard isIPadDevice, #available(iOS 14.0, *) else { return }
            NotificationCenter.default.removeObserver(self, name: .GCKeyboardDidConnect, object: nil)
            NotificationCenter.default.removeObserver(self, name: .GCKeyboardDidDisconnect, object: nil)
            hardwareKeyboardInput?.keyChangedHandler = nil
            hardwareKeyboardInput = nil
        }

        @available(iOS 14.0, *)
        private func bindHardwareKeyboard(_ keyboard: GCKeyboard) {
            hardwareKeyboardInput = keyboard.keyboardInput
            hardwareKeyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
                self?.handleHardwareKeyboardKey(keyCode: keyCode, pressed: pressed)
            }
        }

        @available(iOS 14.0, *)
        @objc private func hardwareKeyboardDidConnect(_ notification: Notification) {
            guard let keyboard = notification.object as? GCKeyboard else { return }
            bindHardwareKeyboard(keyboard)
        }

        @available(iOS 14.0, *)
        @objc private func hardwareKeyboardDidDisconnect(_: Notification) {
            hardwareKeyboardInput?.keyChangedHandler = nil
            if let keyboard = GCKeyboard.coalesced {
                bindHardwareKeyboard(keyboard)
            } else {
                hardwareKeyboardInput = nil
            }
        }

        @available(iOS 14.0, *)
        private func handleHardwareKeyboardKey(keyCode: GCKeyCode, pressed: Bool) {
            if let direction = directionKey(for: keyCode) {
                setKeyboardDirection(direction, active: pressed)
                return
            }

            guard pressed, let action = gameInputAction(for: keyCode) else { return }
            handleKeyboardAction(action)
        }

        @available(iOS 14.0, *)
        private func directionKey(for keyCode: GCKeyCode) -> DirectionKey? {
            guard let usage = UIKeyboardHIDUsage(rawValue: Int(keyCode.rawValue)) else { return nil }
            switch usage {
            case .keyboardA, .keyboardLeftArrow:
                return .left
            case .keyboardD, .keyboardRightArrow:
                return .right
            case .keyboardW, .keyboardUpArrow:
                return .up
            case .keyboardS, .keyboardDownArrow:
                return .down
            default:
                return nil
            }
        }

        @available(iOS 14.0, *)
        private func gameInputAction(for keyCode: GCKeyCode) -> GameInputAction? {
            guard let usage = UIKeyboardHIDUsage(rawValue: Int(keyCode.rawValue)) else { return nil }
            switch usage {
            case .keyboardTab:
                return .nextCluster
            case .keyboardReturnOrEnter, .keyboardSpacebar:
                return .confirmCluster
            case .keyboardEscape:
                return .clearSelection
            default:
                return nil
            }
        }

        /// Drive tilt-based gravity from CoreMotion on a background queue to avoid blocking SpriteKit.
        func startDeviceMotion() {
            guard motionManager.isDeviceMotionAvailable else {
                updateGravity(dx: defaultGravity.dx, dy: defaultGravity.dy)
                return
            }

            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates(
                to: motionQueue,
                withHandler: deviceMotionHandler(for: self)
            )
        }

        func stopDeviceMotion() {
            motionManager.stopDeviceMotionUpdates()
            restoreDefaultGravityIfNeeded()
        }

    #endif
}

#if os(iOS)
    /// Creates a CoreMotion handler that hops back to the main actor before mutating scene state.
    private func deviceMotionHandler(for scene: PotatoGameScene) -> CMDeviceMotionHandler {
        { [weak scene] motion, _ in
            guard let gravity = motion?.gravity else { return }
            let gx = gravity.x
            let gy = gravity.y

            let deadzone = 0.02
            guard abs(gx) >= deadzone || abs(gy) >= deadzone else { return }

            Task { @MainActor [weak scene] in
                guard let scene else { return }
                guard scene.hasKeyboardGravityOverride == false,
                      scene.hasControllerGravityOverride == false,
                      scene.isPaused == false
                else { return }

                let dx = CGFloat(gx) * scene.gravityMagnitude
                let dy = CGFloat(gy) * scene.gravityMagnitude
                scene.updateGravity(dx: dx, dy: dy)
            }
        }
    }
#endif
