// UniverseSceneController.swift
// Memori

import SwiftUI
import SceneKit
import simd
import AVKit

final class UniverseSceneController: NSObject, ObservableObject, SCNSceneRendererDelegate {

    let scene  = SCNScene()
    let camera = SCNNode()

    var yaw:            Float = 0
    var pitch:          Float = 0.15
    var cameraDistance: Float = 6.4
    var lookTarget = SCNVector3(0, 0, 0)

    var panVelocity       = SIMD2<Float>(0, 0)
    var isDragging        = false
    private var lastUpdate: TimeInterval = 0

    // Daily globe
    let dailyGlobeGroup = SCNNode()
    private var dailyGlobeSpinV = SIMD2<Float>(0, 0)
    var isDraggingGlobe = false

    // Photo badge nodes live in a static group. Their positions are recomputed
    // from the spinning globe each frame while their orientation stays upright.
    private var photoPinNodes: [UUID: SCNNode] = [:]
    private var photoPinDirections: [UUID: SIMD3<Float>] = [:]
    private var photoPinSignatures: [UUID: Int] = [:]
    private var shellBadgeNodes: [SCNNode] = []
    private var shellBadgeDirections: [SIMD3<Float>] = []
    let pinGroup = SCNNode()  // never animated — sits still in world space

    private enum BadgeLayout {
        static let surfaceRadius: Float = 1.24
        static let shellRadius: Float = 1.18
        static let minScale: Float = 0.42
        static let maxScale: Float = 1.46
        static let edgeFadeStart: Float = -0.12
        static let edgeFadeEnd: Float = 0.20
        static let shellCount = 54
    }

    // Custom globe nodes
    weak var scnView: SCNView?

    override init() {
        super.init()
        scene.background.contents = UIColor.clear
        setupCamera()
        setupLighting()
        setupDailyGlobe()
    }

    // MARK: - Setup

    private func setupCamera() {
        camera.camera              = SCNCamera()
        camera.camera?.zFar        = 2000
        camera.camera?.zNear       = 0.1
        camera.camera?.fieldOfView = 65
        scene.rootNode.addChildNode(camera)
        applyCameraTransform()
    }

    private func setupLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type  = .ambient
        ambient.light?.color = UIColor(white: 0.10, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type      = .directional
        key.light?.color     = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)
        key.light?.intensity = 800
        key.position = SCNVector3(-5, 8, 6)
        key.look(at: .init(0, 0, 0))
        scene.rootNode.addChildNode(key)
    }

    private func setupDailyGlobe() {
        scene.rootNode.addChildNode(dailyGlobeGroup)
        scene.rootNode.addChildNode(pinGroup)   // pins live here, not on spinning group

        // The "globe" is now the memory badges themselves. This invisible
        // sphere exists only so the badge collection can be grabbed anywhere.
        let dragGeo = SCNSphere(radius: 1.78); dragGeo.segmentCount = 16
        let dragMat = SCNMaterial()
        dragMat.lightingModel = .constant
        dragMat.diffuse.contents = UIColor.clear
        dragMat.transparency = 0.001
        dragMat.colorBufferWriteMask = []
        dragMat.writesToDepthBuffer = false
        dragGeo.firstMaterial = dragMat
        let dragNode = SCNNode(geometry: dragGeo)
        dragNode.name = "dailyGlobe"
        dailyGlobeGroup.addChildNode(dragNode)

        setupShellBadges()
    }

    // MARK: - Photo pins on globe surface

    private func setupShellBadges() {
        guard shellBadgeNodes.isEmpty else { return }

        let shellImage = Self.makeCircleImage(
            size: CGSize(width: 128, height: 128),
            fill: UIColor(red: 0.50, green: 0.35, blue: 0.23, alpha: 1),
            photo: nil
        )

        for index in 0..<BadgeLayout.shellCount {
            let direction = Self.badgeDirection(index: index, count: BadgeLayout.shellCount)
            let size = CGFloat(0.24 + Float(index % 5) * 0.012)
            let geo = SCNPlane(width: size, height: size)
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = shellImage
            mat.emission.contents = UIColor(red: 0.18, green: 0.11, blue: 0.06, alpha: 1)
            mat.isDoubleSided = true
            mat.transparencyMode = .rgbZero
            mat.writesToDepthBuffer = false
            geo.firstMaterial = mat

            let node = SCNNode(geometry: geo)
            node.name = "shellBadge"
            pinGroup.addChildNode(node)
            shellBadgeNodes.append(node)
            shellBadgeDirections.append(direction)
        }
    }

    /// Place photo badges on the globe with an even spiral layout.
    func updatePhotoPins(snippets: [MediaSnippet]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Remove stale pins
            let currentIDs = Set(snippets.map { $0.id })
            let staleIDs = self.photoPinNodes.keys.filter { !currentIDs.contains($0) }
            for id in staleIDs {
                self.photoPinNodes[id]?.removeFromParentNode()
                self.photoPinNodes.removeValue(forKey: id)
                self.photoPinDirections.removeValue(forKey: id)
                self.photoPinSignatures.removeValue(forKey: id)
            }

            let ordered = snippets.sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id.uuidString < $1.id.uuidString
            }

            for (index, snippet) in ordered.enumerated() {
                self.photoPinDirections[snippet.id] = Self.badgeDirection(index: index, count: ordered.count)
                let signature = Self.badgeSignature(for: snippet)
                if self.photoPinSignatures[snippet.id] != signature {
                    self.photoPinNodes[snippet.id]?.removeFromParentNode()
                    self.photoPinNodes.removeValue(forKey: snippet.id)
                    self.addPhotoPin(for: snippet, signature: signature)
                }
            }
            self.updatePhotoPinLayout()
        }
    }

    private func addPhotoPin(for snippet: MediaSnippet, signature: Int) {
        // Container anchored to the globe surface. Its position follows the
        // spinning globe, while its orientation is copied from the camera so it
        // stays upright instead of rolling with the surface.
        let pinRoot = SCNNode()
        pinRoot.name = "photoPin:\(snippet.id.uuidString)"

        let pinSize: CGFloat = 0.34

        // Soft outer badge keeps every memory circular and readable.
        let ringGeo = SCNPlane(width: pinSize + 0.08, height: pinSize + 0.08)
        let ringImg = Self.makeCircleImage(
            size: CGSize(width: 128, height: 128),
            fill: UIColor(red: 0.63, green: 0.44, blue: 0.31, alpha: 1),
            photo: nil
        )
        let ringMat = SCNMaterial()
        ringMat.lightingModel    = .constant
        ringMat.diffuse.contents = ringImg
        ringMat.isDoubleSided    = true
        ringMat.transparencyMode = .rgbZero
        ringMat.writesToDepthBuffer = false
        ringGeo.firstMaterial = ringMat
        pinRoot.addChildNode(SCNNode(geometry: ringGeo))

        // Photo circle on top
        let photoGeo = SCNPlane(width: pinSize, height: pinSize)
        let photoImg: UIImage
        if let data = snippet.imageData, let raw = UIImage(data: data) {
            photoImg = Self.makeCircleImage(
                size: CGSize(width: 256, height: 256),
                fill: UIColor(red: 0.14, green: 0.10, blue: 0.07, alpha: 1),
                photo: raw
            )
        } else {
            photoImg = Self.makeCircleImage(
                size: CGSize(width: 128, height: 128),
                fill: UIColor(red: 0.40, green: 0.28, blue: 0.18, alpha: 1),
                photo: nil
            )
        }
        let photoMat = SCNMaterial()
        photoMat.lightingModel    = .constant
        photoMat.diffuse.contents = photoImg
        photoMat.isDoubleSided    = true
        photoMat.transparencyMode = .rgbZero
        photoMat.writesToDepthBuffer = false
        photoGeo.firstMaterial = photoMat
        let photoNode = SCNNode(geometry: photoGeo)
        photoNode.position = SCNVector3(0, 0, 0.002)
        pinRoot.addChildNode(photoNode)

        // Parent to the static pinGroup; updatePhotoPinLayout moves it from the
        // globe's animated surface transform while preserving screen orientation.
        pinGroup.addChildNode(pinRoot)
        photoPinNodes[snippet.id] = pinRoot
        photoPinSignatures[snippet.id] = signature
    }

    private static func badgeSignature(for snippet: MediaSnippet) -> Int {
        var hasher = Hasher()
        hasher.combine(snippet.id)
        hasher.combine(snippet.date.timeIntervalSinceReferenceDate)
        hasher.combine(snippet.text)
        hasher.combine(snippet.videoPath)
        hasher.combine(snippet.colorHex)

        if let data = snippet.imageData {
            hasher.combine(data.count)
            for byte in data.prefix(24) { hasher.combine(byte) }
            for byte in data.suffix(24) { hasher.combine(byte) }
        } else {
            hasher.combine(-1)
        }

        return hasher.finalize()
    }

    private static func badgeDirection(index: Int, count: Int) -> SIMD3<Float> {
        guard count > 1 else { return SIMD3<Float>(0, 0, 1) }

        let n = Float(max(count, 1))
        let i = Float(index)
        let goldenAngle = Float.pi * (3.0 - Float(sqrt(5.0)))
        let y = 1.0 - ((i + 0.5) / n) * 2.0
        let radius = sqrt(max(0.0, 1.0 - y * y))
        let theta = i * goldenAngle

        // Axis mapping puts the spiral's broadest band around the visible face.
        return simd_normalize(SIMD3<Float>(
            radius * sin(theta),
            y,
            radius * cos(theta)
        ))
    }

    private func updatePhotoPinLayout() {
        let globeTransform = dailyGlobeGroup.presentation.simdWorldTransform
        let globeCenter = SIMD3<Float>(
            globeTransform.columns.3.x,
            globeTransform.columns.3.y,
            globeTransform.columns.3.z
        )
        let cameraPosition = camera.presentation.simdWorldPosition
        let cameraOrientation = camera.presentation.simdWorldOrientation

        for (index, node) in shellBadgeNodes.enumerated() where index < shellBadgeDirections.count {
            let dir = shellBadgeDirections[index]
            let localPos = dir * BadgeLayout.shellRadius
            let world4 = globeTransform * SIMD4<Float>(localPos.x, localPos.y, localPos.z, 1)
            let worldPos = SIMD3<Float>(world4.x, world4.y, world4.z)
            let surfaceNormal = simd_normalize(worldPos - globeCenter)
            let towardCamera = simd_normalize(cameraPosition - worldPos)
            let frontness = simd_dot(surfaceNormal, towardCamera)
            let t = Self.clamp01((frontness - BadgeLayout.edgeFadeStart) / (BadgeLayout.edgeFadeEnd - BadgeLayout.edgeFadeStart))
            let centerWeight = Float(pow(Double(max(frontness, 0)), 0.78))
            let scale = 0.72 + centerWeight * 0.72

            node.simdWorldPosition = worldPos
            node.simdOrientation = cameraOrientation
            node.simdScale = SIMD3<Float>(repeating: scale)
            node.opacity = CGFloat(0.28 + t * 0.42)
            node.isHidden = t <= 0.01
            node.renderingOrder = Int(400 + max(frontness, 0) * 80)
        }

        for (id, node) in photoPinNodes {
            guard let dir = photoPinDirections[id] else { continue }
            let localPos = dir * BadgeLayout.surfaceRadius
            let world4 = globeTransform * SIMD4<Float>(localPos.x, localPos.y, localPos.z, 1)
            let worldPos = SIMD3<Float>(world4.x, world4.y, world4.z)
            let surfaceNormal = simd_normalize(worldPos - globeCenter)
            let towardCamera = simd_normalize(cameraPosition - worldPos)
            let frontness = simd_dot(surfaceNormal, towardCamera)
            let t = Self.clamp01((frontness - BadgeLayout.edgeFadeStart) / (BadgeLayout.edgeFadeEnd - BadgeLayout.edgeFadeStart))
            let centerWeight = Float(pow(Double(max(frontness, 0)), 0.72))
            let scale = BadgeLayout.minScale + centerWeight * (BadgeLayout.maxScale - BadgeLayout.minScale)

            node.simdWorldPosition = worldPos
            node.simdOrientation = cameraOrientation
            node.simdScale = SIMD3<Float>(repeating: scale)
            node.opacity = CGFloat(t)
            node.isHidden = t <= 0.02
            node.renderingOrder = Int(1000 + max(frontness, 0) * 100)
        }
    }

    private static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    /// Renders a circular-masked UIImage at the given size.
    /// `fill` is used when `photo` is nil (journal-only pins).
    /// Uses clear background so SceneKit's rgbZero transparency clips the corners.
    private static func makeCircleImage(size: CGSize, fill: UIColor, photo: UIImage?) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.clear.setFill()
            ctx.fill(rect)
            UIBezierPath(ovalIn: rect).addClip()
            if let photo {
                let aspect = photo.size.width / max(photo.size.height, 1)
                let drawRect: CGRect
                if aspect > 1 {
                    let h = size.height
                    let w = h * aspect
                    drawRect = CGRect(x: (size.width - w) / 2, y: 0, width: w, height: h)
                } else {
                    let w = size.width
                    let h = w / max(aspect, 0.001)
                    drawRect = CGRect(x: 0, y: (size.height - h) / 2, width: w, height: h)
                }
                photo.draw(in: drawRect)
            } else {
                fill.setFill()
                ctx.fill(rect)
            }
        }
    }


    // MARK: - Custom globes
    // Custom globes are rendered as SwiftUI MiniGlobeView — no SceneKit nodes needed.

    func addGlobeNode(globe: MemoryGlobe) { }
    func removeGlobeNode(id: UUID) { }
    func flyTo(globeID: UUID) { }

    // MARK: - Camera

    func applyCameraTransform() {
        let x = lookTarget.x + cameraDistance * cos(pitch) * sin(yaw)
        let y = lookTarget.y + cameraDistance * sin(pitch)
        let z = lookTarget.z + cameraDistance * cos(pitch) * cos(yaw)
        camera.position = SCNVector3(x, y, z)
        camera.look(at: lookTarget)
    }

    func panTarget(dx: Float, dy: Float) {
        let s: Float = cameraDistance * 0.001
        let fwd = simd_normalize(SIMD3<Float>(
            lookTarget.x - camera.position.x,
            lookTarget.y - camera.position.y,
            lookTarget.z - camera.position.z
        ))
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(fwd, worldUp))
        let up    = simd_normalize(simd_cross(right, fwd))
        lookTarget.x -= right.x * dx * s + up.x * (-dy) * s
        lookTarget.y -= right.y * dx * s + up.y * (-dy) * s
        lookTarget.z -= right.z * dx * s + up.z * (-dy) * s
        applyCameraTransform()
    }

    func zoomDelta(factor: Float) {
        cameraDistance = max(1.5, min(25.0, cameraDistance / factor))
        applyCameraTransform()
    }

    func resetView(animated: Bool) {
        yaw = 0; pitch = 0.15; cameraDistance = 6.4
        lookTarget = SCNVector3(0, 0, 0)
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            applyCameraTransform()
            SCNTransaction.commit()
        } else {
            applyCameraTransform()
        }
    }

    func spinGlobe(dx: Float, dy: Float) {
        let s: Float = 0.0048
        let qx = simd_quatf(angle: dx * s, axis: SIMD3<Float>(0, 1, 0))
        let qy = simd_quatf(angle: dy * s, axis: SIMD3<Float>(1, 0, 0))
        dailyGlobeGroup.simdOrientation = simd_mul(qx, simd_mul(qy, dailyGlobeGroup.simdOrientation))
    }

    // MARK: - Renderer

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastUpdate == 0 { lastUpdate = time }
        let dt = Float(time - lastUpdate)
        lastUpdate = time
        guard dt < 0.1 else { return }

        if !isDragging && simd_length(panVelocity) > 1e-4 {
            panTarget(dx: panVelocity.x * dt * 60, dy: panVelocity.y * dt * 60)
            panVelocity *= exp(-2.8 * dt)
            if simd_length(panVelocity) < 1e-3 { panVelocity = .zero }
        }
        if !isDraggingGlobe && simd_length(dailyGlobeSpinV) > 1e-4 {
            spinGlobe(dx: dailyGlobeSpinV.x * dt * 60, dy: dailyGlobeSpinV.y * dt * 60)
            dailyGlobeSpinV *= exp(-1.35 * dt)
            if simd_length(dailyGlobeSpinV) < 0.04 { dailyGlobeSpinV = .zero }
        }

        updatePhotoPinLayout()
    }

    func setGlobeSpinVelocity(_ v: SIMD2<Float>) { dailyGlobeSpinV = v }
    func setPanVelocity(_ v: SIMD2<Float>)        { panVelocity     = v }
    func setLookVelocity(_ v: SIMD2<Float>)       { }

    // MARK: - Hit test

    enum HitType { case dailyGlobe, customGlobe }

    func hitTestResult(at pt: CGPoint) -> (type: HitType, key: String, screenPt: CGPoint)? {
        guard let v = scnView else { return nil }
        let hits = v.hitTest(pt, options: [
            .firstFoundOnly: false,
            .backFaceCulling: false,
            .boundingBoxOnly: false
        ])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let n = node {
                guard let name = n.name else { node = n.parent; continue }
                if name == "dailyGlobe" { return (.dailyGlobe, "daily", pt) }
                if name.hasPrefix("globe:"),
                   let id = UUID(uuidString: String(name.dropFirst(6))) {
                    return (.customGlobe, id.uuidString, pt)
                }
                node = n.parent
            }
        }
        return nil
    }

    // MARK: - Helpers

}

