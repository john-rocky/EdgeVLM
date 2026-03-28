//
// ARAnnotation.swift
// EdgeVLM
//
// Data model for AR annotations placed in 3D space.
//

import Foundation
import simd

/// Represents a single annotation placed in the AR scene.
struct ARAnnotation: Identifiable {
    let id = UUID()
    let text: String
    let transform: simd_float4x4
}
