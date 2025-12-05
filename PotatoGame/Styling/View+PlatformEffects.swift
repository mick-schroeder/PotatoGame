// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI

#if os(iOS)
    extension View {
        @ViewBuilder
        func platformGlassEffect(in shape: some Shape, interactive: Bool, tint: Color? = nil, clear: Bool = false) -> some View {
            if #available(iOS 26.0, *) {
                let baseGlass: Glass = {
                    if clear { return .clear }
                    if let tint { return .regular.tint(tint) }
                    return .regular
                }()
                let glass = interactive ? baseGlass.interactive() : baseGlass

                glassEffect(glass, in: shape)
                    .glassEffectTransition(.materialize)
            } else {
                background {
                    shape.glassed()
                        .overlay {
                            if let tint {
                                shape.fill(tint.opacity(0.12))
                            }
                        }
                }
            }
        }

        @ViewBuilder
        func platformGlassButtonStyle(prominent: Bool) -> some View {
            if #available(iOS 26.0, *) {
                if prominent {
                    buttonStyle(.glassProminent)
                } else {
                    buttonStyle(.glass)
                }
            } else {
                if prominent {
                    buttonStyle(.borderedProminent)
                } else {
                    buttonStyle(.bordered)
                }
            }
        }
    }

#elseif os(macOS)
    extension View {
        @ViewBuilder
        func platformGlassEffect(in shape: some Shape, interactive: Bool, tint: Color? = nil, clear: Bool = false) -> some View {
            if #available(macOS 26, *) {
                let baseGlass: Glass = {
                    if clear { return .clear }
                    if let tint { return .regular.tint(tint) }
                    return .regular
                }()
                let glass = interactive ? baseGlass.interactive() : baseGlass

                glassEffect(glass, in: shape)
                    .glassEffectTransition(.materialize)
            } else {
                background {
                    shape.glassed()
                        .overlay {
                            if let tint {
                                shape.fill(tint.opacity(0.12))
                            }
                        }
                }
            }
        }

        @ViewBuilder
        func platformGlassButtonStyle(prominent: Bool) -> some View {
            if #available(macOS 26, *) {
                if prominent {
                    buttonStyle(.glassProminent)
                } else {
                    buttonStyle(.glass)
                }
            } else {
                if prominent {
                    buttonStyle(.borderedProminent)
                } else {
                    buttonStyle(.bordered)
                }
            }
        }
    }
#else
    extension View {
        @ViewBuilder
        func platformGlassEffect(in shape: some Shape, interactive _: Bool, tint: Color? = nil, clear _: Bool = false) -> some View {
            background {
                shape.glassed()
                    .overlay {
                        if let tint {
                            shape.fill(tint.opacity(0.12))
                        }
                    }
            }
        }

        @ViewBuilder
        func platformGlassButtonStyle(prominent: Bool) -> some View {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
#endif
