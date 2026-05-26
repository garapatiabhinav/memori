// UniverseSceneView.swift
// Memori

import SwiftUI
import SceneKit
import simd

// MARK: - SCNView Bridge

struct UniverseSceneView: UIViewRepresentable {
    let controller:   UniverseSceneController
    let onDailyTapped:  () -> Void
    let onGlobeTapped:  (UUID) -> Void

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene            = controller.scene
        v.pointOfView      = controller.camera
        v.backgroundColor  = .clear
        v.isOpaque         = false
        v.isPlaying        = true
        v.antialiasingMode = .multisampling4X
        v.delegate         = controller
        v.autoenablesDefaultLighting = false
        controller.scnView = v

        let pan   = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let tap   = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        pinch.delegate = context.coordinator
        pan.delegate   = context.coordinator
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(pinch)
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller,
                    onDailyTapped: onDailyTapped,
                    onGlobeTapped: onGlobeTapped)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let controller:    UniverseSceneController
        let onDailyTapped: () -> Void
        let onGlobeTapped: (UUID) -> Void
        private var draggingGlobe = false

        init(controller: UniverseSceneController,
             onDailyTapped: @escaping () -> Void,
             onGlobeTapped: @escaping (UUID) -> Void) {
            self.controller    = controller
            self.onDailyTapped = onDailyTapped
            self.onGlobeTapped = onGlobeTapped
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view else { return }
            let t = g.translation(in: v)
            switch g.state {
            case .began:
                let hit = controller.hitTestResult(at: g.location(in: v))
                draggingGlobe              = hit?.type == .dailyGlobe
                controller.isDragging      = !draggingGlobe
                controller.isDraggingGlobe = draggingGlobe
                controller.setLookVelocity(.zero)
            case .changed:
                if draggingGlobe {
                    controller.spinGlobe(dx: Float(t.x), dy: Float(t.y))
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.35)
                } else {
                    controller.panTarget(dx: Float(t.x), dy: Float(t.y))
                }
                g.setTranslation(.zero, in: v)
            case .ended, .cancelled:
                let vel = g.velocity(in: v)
                let s: Float = draggingGlobe ? (1.0 / 60.0) : 0.00005
                var ang = SIMD2<Float>(Float(vel.x) * s, Float(vel.y) * s)
                let mag = simd_length(ang)
                let mx: Float = draggingGlobe ? 42.0 : 1.5
                if mag > mx { ang = ang / mag * mx }
                if draggingGlobe { controller.setGlobeSpinVelocity(ang) }
                else             { controller.setPanVelocity(ang) }
                controller.isDragging      = false
                controller.isDraggingGlobe = false
            default: break
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            if g.state == .changed { controller.zoomDelta(factor: Float(g.scale)); g.scale = 1 }
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            // Custom globes are now SwiftUI MiniGlobeView — SceneKit tap only
            // handles the background pan/zoom; do nothing on empty taps.
            guard let v = g.view else { return }
            guard let hit = controller.hitTestResult(at: g.location(in: v)) else { return }
            switch hit.type {
            case .dailyGlobe: break   // handled by BadgeGlobeView in SwiftUI
            case .customGlobe: break  // handled by MiniGlobeView in SwiftUI
            }
        }
    }
}

