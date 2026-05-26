// BadgeGlobeView.swift
// Memori

import SwiftUI
import simd

// MARK: - SwiftUI Daily Badge Globe

struct BadgeGlobeView: View {
    let snippets: [MediaSnippet]
    let onBadgeTap: (MediaSnippet) -> Void
    var onBadgeDelete: ((MediaSnippet) -> Void)? = nil
    var onGlobeTap: (() -> Void)? = nil

    @State private var orientation = simd_quatd(angle: -0.16, axis: SIMD3<Double>(1, 0, 0))
    @State private var dragStartOrientation = simd_quatd(angle: 0, axis: SIMD3<Double>(0, 1, 0))
    @State private var dragStartVector = SIMD3<Double>(0, 0, 1)
    @State private var angularVelocity = SIMD3<Double>(0, 0, 0)
    @State private var isDragging = false
    @State private var lastTick = Date()
    @State private var snippetToDelete: MediaSnippet? = nil
    @State private var showDeleteAlert = false

    // Haptics — tick every ~22° of rotation during inertia
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    @State private var lastHapticAngle: Double = 0
    private let hapticTickRad: Double = 0.38   // ~22°

    private let maxAngularVelocity = 2.4
    private let damping = 1.05
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let baseRadius = min(geo.size.width, geo.size.height) * 0.48
            let radius = baseRadius
            let photoBadges = snippets.sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id.uuidString < $1.id.uuidString
            }
            let shellCount = max(44, min(68, 58 - min(photoBadges.count, 18)))

            ZStack {
                ForEach(0..<shellCount, id: \.self) { index in
                    let point = projectedPoint(
                        direction: badgeDirection(index: index, count: shellCount),
                        center: center,
                        radius: radius
                    )
                    Circle()
                        .fill(Memori.Color.accentMuted.opacity(0.95))
                        .overlay(
                            Circle()
                                .stroke(Memori.Color.inkFaint.opacity(0.22), lineWidth: 1)
                        )
                        .frame(width: point.size * 0.72, height: point.size * 0.72)
                        .position(point.position)
                        .opacity(point.opacity * 0.72)
                        .zIndex(point.depth)
                }

                ForEach(Array(photoBadges.enumerated()), id: \.element.id) { index, snippet in
                    let point = projectedPoint(
                        direction: badgeDirection(index: index, count: max(photoBadges.count, 1)),
                        center: center,
                        radius: radius
                    )
                    PhotoBadge(snippet: snippet)
                        .frame(width: point.size, height: point.size)
                        .position(point.position)
                        .opacity(point.opacity)
                        .zIndex(100 + point.depth)
                        .contentShape(Circle())
                        .highPriorityGesture(
                            TapGesture().onEnded {
                                onBadgeTap(snippet)
                            }
                        )
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                snippetToDelete = snippet
                                showDeleteAlert = true
                            }
                        )
                }
            }
            .contentShape(Circle().size(CGSize(width: radius * 2, height: radius * 2))
                .offset(x: center.x - radius, y: center.y - radius))
            .gesture(dragGesture(center: center, radius: radius, photoBadges: photoBadges))
            .simultaneousGesture(
                TapGesture().onEnded { onGlobeTap?() }
            )
            
            .alert("Delete this memory?", isPresented: $showDeleteAlert, presenting: snippetToDelete) { s in
                Button("Delete", role: .destructive) {
                    onBadgeDelete?(s)
                }
                Button("Cancel", role: .cancel) {}
            } message: { s in
                Text(s.text.isEmpty ? "This will permanently remove this memory." : "\"\(s.text)\" will be permanently removed.")
            }
        }
        .onAppear { hapticLight.prepare(); hapticMedium.prepare() }
        .onReceive(timer) { now in
            let dt = min(now.timeIntervalSince(lastTick), 1.0 / 20.0)
            lastTick = now
            guard !isDragging else { return }

            let speed = simd_length(angularVelocity)
            guard speed > 0.0001 else { return }

            let delta = simd_quatd(angle: speed * dt, axis: angularVelocity / speed)
            orientation = simd_mul(delta, orientation)
            angularVelocity *= exp(-damping * dt)
            if simd_length(angularVelocity) < 0.01 { angularVelocity = .zero }

            // Haptic tick every ~22° of rotation during inertia
            let totalAngle = speed * dt
            lastHapticAngle += totalAngle
            if lastHapticAngle >= hapticTickRad {
                lastHapticAngle = 0
                hapticLight.impactOccurred(intensity: CGFloat(min(speed / maxAngularVelocity, 1.0)) * 0.55)
            }
        }
    }

    private func dragGesture(center: CGPoint, radius: CGFloat, photoBadges: [MediaSnippet]) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if !isDragging {
                    dragStartOrientation = orientation
                    dragStartVector = trackballVector(at: value.startLocation, center: center, radius: radius)
                    angularVelocity = .zero
                    lastHapticAngle = 0
                    isDragging = true
                    hapticMedium.impactOccurred(intensity: 0.4)
                }

                let currentVector = trackballVector(at: value.location, center: center, radius: radius)
                let delta = Self.rotation(from: dragStartVector, to: currentVector)
                orientation = simd_mul(delta, dragStartOrientation)
            }
            .onEnded { value in
                let currentVector = trackballVector(at: value.location, center: center, radius: radius)
                let projectedVector = trackballVector(at: value.predictedEndLocation, center: center, radius: radius)
                let delta = Self.rotation(from: currentVector, to: projectedVector)
                let angle = min(delta.angle, .pi)
                var nextVelocity = delta.axis * (angle / 0.45)
                let speed = simd_length(nextVelocity)
                if speed > maxAngularVelocity {
                    nextVelocity = nextVelocity / speed * maxAngularVelocity
                }
                angularVelocity = nextVelocity
                isDragging = false

            }
    }

    /// Rotates the globe so the badge currently closest to the front-center snaps exactly to center.
    private func snapClosestBadgeToCenter(photoBadges: [MediaSnippet]) {
        let count = photoBadges.count
        guard count > 0 else { return }

        // Find direction of each badge after current orientation and pick the most front-facing
        var bestDot = -Double.infinity
        var bestDir = SIMD3<Double>(0, 0, 1)

        for index in 0..<count {
            let dir = badgeDirection(index: index, count: count)
            let rotated = orientation.act(dir)
            if rotated.z > bestDot {
                bestDot = rotated.z
                bestDir = dir
            }
        }

        // Build the shortest rotation that brings bestDir to (0,0,1)
        let rotated = orientation.act(bestDir)
        let target = SIMD3<Double>(0, 0, 1)
        let snapQuat = Self.rotation(from: rotated, to: target)

        // Apply with a gentle spring — just set a small velocity toward the target
        // by composing the correction into current orientation over a short arc
        angularVelocity = .zero
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            orientation = simd_mul(snapQuat, orientation)
        }
        hapticMedium.impactOccurred(intensity: 0.65)
    }

    private func projectedPoint(direction: SIMD3<Double>, center: CGPoint, radius: CGFloat) -> (position: CGPoint, size: CGFloat, opacity: Double, depth: Double) {
        let p = rotate(direction)
        let frontness = max(-0.28, min(1.0, p.z))
        let visible = max(0.0, min(1.0, (frontness + 0.18) / 0.42))
        let centerWeight = pow(max(frontness, 0.0), 0.72)
        let perspective = 0.86 + centerWeight * 0.16
        let x = center.x + CGFloat(p.x) * radius * perspective
        let y = center.y - CGFloat(p.y) * radius * perspective
        let size = radius * CGFloat(0.10 + centerWeight * 0.22)

        return (
            CGPoint(x: x, y: y),
            max(16, size),
            0.18 + visible * 0.82,
            frontness
        )
    }

    private func rotate(_ point: SIMD3<Double>) -> SIMD3<Double> {
        orientation.act(point)
    }

    private func trackballVector(at location: CGPoint, center: CGPoint, radius: CGFloat) -> SIMD3<Double> {
        let x = Double((location.x - center.x) / radius)
        let y = Double((center.y - location.y) / radius)
        let lengthSquared = x * x + y * y

        if lengthSquared <= 1 {
            return simd_normalize(SIMD3<Double>(x, y, sqrt(1 - lengthSquared)))
        }

        return simd_normalize(SIMD3<Double>(x, y, 0))
    }

    private static func rotation(from start: SIMD3<Double>, to end: SIMD3<Double>) -> simd_quatd {
        let dot = max(-1.0, min(1.0, simd_dot(start, end)))
        if dot > 0.9999 { return simd_quatd(angle: 0, axis: SIMD3<Double>(0, 1, 0)) }

        var axis = simd_cross(start, end)
        if simd_length(axis) < 0.0001 {
            axis = abs(start.x) < 0.9 ? simd_cross(start, SIMD3<Double>(1, 0, 0)) : simd_cross(start, SIMD3<Double>(0, 1, 0))
        }

        return simd_quatd(angle: acos(dot), axis: simd_normalize(axis))
    }

    private func badgeDirection(index: Int, count: Int) -> SIMD3<Double> {
        guard count > 1 else { return SIMD3<Double>(0, 0, 1) }
        let n = Double(max(count, 1))
        let i = Double(index)
        let goldenAngle = Double.pi * (3.0 - sqrt(5.0))
        let y = 1.0 - ((i + 0.5) / n) * 2.0
        let r = sqrt(max(0.0, 1.0 - y * y))
        let theta = i * goldenAngle

        return simd_normalize(SIMD3<Double>(
            r * sin(theta),
            y,
            r * cos(theta)
        ))
    }
}

struct PhotoBadge: View {
    let snippet: MediaSnippet

    var body: some View {
        ZStack {
            Circle()
                .fill(Memori.Color.accent)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            }
        }
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Memori.Color.paperBg.opacity(0.9), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
    }

    private var image: UIImage? {
        guard let data = snippet.imageData else { return nil }
        return UIImage(data: data)
    }
}
