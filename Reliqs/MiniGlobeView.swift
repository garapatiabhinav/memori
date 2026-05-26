// MiniGlobeView.swift
// Memori

import SwiftUI
import simd

struct MiniGlobeView: View {
    let name: String
    var snippets: [MediaSnippet] = []

    @Binding var isEditing: Bool
    var onPositionChange: ((CGSize) -> Void)? = nil
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil
    var onDeleteMemoriesOnly: (() -> Void)? = nil
    var onReposition: (() -> Void)? = nil

    @State private var orientation     = simd_quatd(angle: 0.1, axis: SIMD3<Double>(0.2, 1, 0.1))
    @State private var dragStartOrient = simd_quatd(angle: 0,   axis: SIMD3<Double>(0, 1, 0))
    @State private var dragStartVec    = SIMD3<Double>(0, 0, 1)
    @State private var angularVelocity = SIMD3<Double>(0, 0, 0)
    @State private var isDragging      = false
    @State private var lastTick        = Date()

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let baseRadius: CGFloat = 52
    private var globeRadius: CGFloat { baseRadius }
    private var shellCount: Int { max(20, min(42, 42 - min(snippets.count, 22))) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ForEach(0..<shellCount, id: \.self) { i in
                    let dir   = badgeDirection(index: i, count: shellCount)
                    let proj  = orientation.act(dir)
                    let front = max(0.0, proj.z)
                    let size  = globeRadius * CGFloat(0.08 + front * 0.10)
                    Circle()
                        .fill(Memori.Color.accentMuted.opacity(0.95))
                        .overlay(Circle().stroke(Memori.Color.inkFaint.opacity(0.25), lineWidth: 0.5))
                        .frame(width: size * 2, height: size * 2)
                        .offset(x: globeRadius * CGFloat(proj.x) * 0.92,
                                y: -globeRadius * CGFloat(proj.y) * 0.92)
                        .opacity(proj.z > -0.15 ? 0.22 + front * 0.55 : 0.0)
                }
                ForEach(Array(snippets.enumerated()), id: \.element.id) { i, snippet in
                    let dir   = badgeDirection(index: i, count: max(snippets.count, 1))
                    let proj  = orientation.act(dir)
                    let front = max(0.0, proj.z)
                    let size  = globeRadius * CGFloat(0.18 + front * 0.12)
                    PhotoBadge(snippet: snippet)
                        .frame(width: size * 2, height: size * 2)
                        .offset(x: globeRadius * CGFloat(proj.x) * 0.92,
                                y: -globeRadius * CGFloat(proj.y) * 0.92)
                        .opacity(proj.z > -0.1 ? 0.2 + front * 0.8 : 0)
                        .zIndex(100 + proj.z)
                }
            }
            .frame(width: globeRadius * 2, height: globeRadius * 2)
            .rotationEffect(.degrees(isEditing ? 2.5 : 0))
            .animation(
                isEditing ? .linear(duration: 0.12).repeatForever(autoreverses: true) : .default,
                value: isEditing
            )
            .contentShape(Circle())
            .overlay(
                LongPressOverlay(
                    isEditing: $isEditing,
                    onTap: onTap,
                    onLongPress: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation { isEditing = true }
                    }
                )
            )
            // Spin gesture — only in normal mode
            .gesture(
                isEditing ? nil : DragGesture(minimumDistance: 3)
                    .onChanged { v in
                        if !isDragging {
                            dragStartOrient = orientation
                            dragStartVec    = trackball(v.startLocation)
                            angularVelocity = .zero
                            isDragging      = true
                        }
                        orientation = simd_mul(
                            arcRotation(from: dragStartVec, to: trackball(v.location)),
                            dragStartOrient
                        )
                    }
                    .onEnded { v in
                        let q = arcRotation(
                            from: trackball(v.location),
                            to: trackball(v.predictedEndLocation)
                        )
                        angularVelocity = q.axis * min(q.angle / 0.45, 3.0)
                        isDragging = false
                    }
            )

            Text(name)
                .font(Memori.Font.sans(10, weight: .medium))
                .foregroundStyle(Memori.Color.inkMid)
                .tracking(0.5)
                .lineLimit(1)
        }
        .onReceive(timer) { now in
            let dt = min(now.timeIntervalSince(lastTick), 0.05)
            lastTick = now
            guard !isDragging else { return }
            let speed = simd_length(angularVelocity)
            if speed > 0.01 {
                let delta = simd_quatd(angle: speed * dt, axis: angularVelocity / speed)
                orientation     = simd_mul(delta, orientation)
                angularVelocity *= exp(-1.4 * dt)
            } else {
                angularVelocity = .zero
                orientation = simd_mul(
                    simd_quatd(angle: 0.008, axis: SIMD3<Double>(0, 1, 0.15)),
                    orientation
                )
            }
        }
    }

    private func trackball(_ pt: CGPoint) -> SIMD3<Double> {
        let x = Double(pt.x / globeRadius)
        let y = Double(-pt.y / globeRadius)
        let l2 = x*x + y*y
        return l2 <= 1 ? simd_normalize(SIMD3(x, y, sqrt(1 - l2)))
                       : simd_normalize(SIMD3(x, y, 0))
    }

    private func arcRotation(from a: SIMD3<Double>, to b: SIMD3<Double>) -> simd_quatd {
        let dot = max(-1.0, min(1.0, simd_dot(a, b)))
        if dot > 0.9999 { return simd_quatd(angle: 0, axis: SIMD3(0, 1, 0)) }
        var axis = simd_cross(a, b)
        if simd_length(axis) < 1e-6 { axis = SIMD3(1, 0, 0) }
        return simd_quatd(angle: acos(dot), axis: simd_normalize(axis))
    }

    private func badgeDirection(index: Int, count: Int) -> SIMD3<Double> {
        guard count > 1 else { return SIMD3<Double>(0, 0, 1) }
        let n = Double(count), i = Double(index)
        let y = 1.0 - ((i + 0.5) / n) * 2.0
        let r = sqrt(max(0.0, 1.0 - y*y))
        let theta = i * Double.pi * (3.0 - sqrt(5.0))
        return simd_normalize(SIMD3<Double>(r * sin(theta), y, r * cos(theta)))
    }
}

// MARK: - LongPressOverlay
// Uses UIKit gesture recognizers directly so tap and long-press are
// unambiguously distinct — SwiftUI's gesture system can't reliably
// differentiate them when combined with simultaneous gestures.

private struct LongPressOverlay: UIViewRepresentable {
    @Binding var isEditing: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        let lp  = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        lp.minimumPressDuration = 0.5
        // Tap requires long-press to fail so they don't race
        tap.require(toFail: lp)

        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(lp)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEditing   = isEditing
        context.coordinator.onTap       = onTap
        context.coordinator.onLongPress = onLongPress
    }

    func makeCoordinator() -> Coordinator { Coordinator(isEditing: isEditing, onTap: onTap, onLongPress: onLongPress) }

    final class Coordinator: NSObject {
        var isEditing:   Bool
        var onTap:       () -> Void
        var onLongPress: () -> Void

        init(isEditing: Bool, onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
            self.isEditing   = isEditing
            self.onTap       = onTap
            self.onLongPress = onLongPress
        }

        @objc func tapped() {
            guard !isEditing else { return }
            onTap()
        }

        @objc func longPressed(_ gr: UILongPressGestureRecognizer) {
            // .began fires as soon as minimumPressDuration elapses, finger still down
            guard gr.state == .began else { return }
            onLongPress()
        }
    }
}
