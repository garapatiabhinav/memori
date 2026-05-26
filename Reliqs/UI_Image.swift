

//
//  Memori
//
//  Created by Abhinav Garapati on 31/08/25.
//
// UIImage+Extensions.swift

// Self-contained: keeps original APIs and adds a flowery background generator.
// Drop into your project and import UIKit & AVFoundation where needed.

// UIImage+Extensions.swift
import UIKit
import AVFoundation
import CoreGraphics

// MARK: - UIImage helpers (existing APIs preserved)
extension UIImage {
    /// Crops the image to a centered square and returns a circular-masked UIImage.
    func circularMaskedSquare() -> UIImage {
        let side = min(size.width, size.height)
        let cropRect = CGRect(
            x: (size.width  - side) * 0.5,
            y: (size.height - side) * 0.5,
            width: side, height: side
        )

        // If cgImage cropping fails, return original
        guard let cg = self.cgImage?.cropping(to: cropRect) else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            UIBezierPath(ovalIn: rect).addClip()
            let img = UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
            img.draw(in: rect)
        }
    }

    /// Returns an upright version of the image (respects orientation)
    func upright() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Flowery background generator
extension UIImage {

    /// Style choices for generated backgrounds
    public enum FloweryStyle {
        case colorful
        case beige
        case dark
    }

    /// Generate a static flowery background image sized to `size`.
    /// - Parameters:
    ///   - style: .colorful | .beige | .dark
    ///   - size: output size in points
    ///   - flowerDensity: approximate flowers per pixel (smaller = fewer flowers)
    ///   - bandCount: number of flowing bands
    ///   - seed: deterministic seed for reproducible results
    /// - Returns: generated UIImage
    public static func floweryBackground(
        _ style: FloweryStyle,
        size: CGSize,
        flowerDensity: CGFloat = 0.0009,
        bandCount: Int = 5,
        seed: Double = Double.random(in: 0...1000)
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        // opaque for performance; dark & beige look fine opaque
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        // tiny deterministic noise function: returns 0..1
        func noise(_ x: Double, _ y: Double, _ s: Double) -> Double {
            let v = sin(x * 12.9898 + y * 78.233 + s) * 43758.5453123
            return v - floor(v)
        }

        // palettes
        func bandPalette(for style: FloweryStyle) -> [UIColor] {
            switch style {
            case .colorful:
                return [
                    UIColor(red: 0.96, green: 0.56, blue: 0.34, alpha: 1.0), // coral
                    UIColor(red: 0.98, green: 0.39, blue: 0.62, alpha: 1.0), // pink
                    UIColor(red: 0.98, green: 0.82, blue: 0.35, alpha: 1.0), // yellow
                    UIColor(red: 0.18, green: 0.72, blue: 0.69, alpha: 1.0), // teal
                    UIColor(red: 0.56, green: 0.44, blue: 0.92, alpha: 1.0)  // purple
                ]
            case .beige:
                return [
                    UIColor(red: 0.95, green: 0.90, blue: 0.82, alpha: 1.0),
                    UIColor(red: 0.98, green: 0.78, blue: 0.58, alpha: 1.0),
                    UIColor(red: 0.86, green: 0.92, blue: 0.88, alpha: 1.0),
                    UIColor(red: 0.95, green: 0.85, blue: 0.76, alpha: 1.0)
                ]
            case .dark:
                return [
                    UIColor(red: 0.85, green: 0.30, blue: 0.30, alpha: 1.0),
                    UIColor(red: 0.45, green: 0.20, blue: 0.60, alpha: 1.0),
                    UIColor(red: 0.00, green: 0.55, blue: 0.50, alpha: 1.0),
                    UIColor(red: 0.95, green: 0.66, blue: 0.16, alpha: 1.0)
                ]
            }
        }

        func backgroundColor(for style: FloweryStyle) -> UIColor {
            switch style {
            case .colorful:
                return UIColor(red: 0.94, green: 0.97, blue: 0.98, alpha: 1.0)
            case .beige:
                return UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1.0)
            case .dark:
                return UIColor(white: 0.06, alpha: 1.0)
            }
        }

        // Draw a single small flower into CGContext at center with radius and color
        func drawFlower(in cg: CGContext, center: CGPoint, radius: CGFloat, color: UIColor, rotation: CGFloat) {
            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.rotate(by: rotation)
            let petalCount = 5
            for i in 0..<petalCount {
                let angle = CGFloat(i) * (2.0 * .pi / CGFloat(petalCount))
                cg.saveGState()
                cg.rotate(by: angle)
                let petalRect = CGRect(x: -radius * 0.5, y: -radius * 1.05, width: radius, height: radius * 1.05)
                let petalPath = UIBezierPath(ovalIn: petalRect)
                color.setFill()
                petalPath.fill()
                cg.restoreGState()
            }
            // center
            let centerRect = CGRect(x: -radius * 0.35, y: -radius * 0.35, width: radius * 0.7, height: radius * 0.7)
            let centerColor = UIColor(red: 1.0, green: 0.95, blue: 0.20, alpha: 1.0)
            centerColor.setFill()
            UIBezierPath(ovalIn: centerRect).fill()
            cg.restoreGState()
        }

        // Draw band lines (multi-directional) into cg
        func drawBands(in cg: CGContext, rectSize: CGSize, bandCount: Int, seed: Double, style: FloweryStyle) {
            // small deterministic RNG based on seed
            var rngState = UInt64(bitPattern: Int64(seed.bitPattern))
            func rnd() -> Double {
                rngState &+= 0x9e3779b97f4a7c15
                var z = rngState
                z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
                z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
                return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
            }

            let w = Double(rectSize.width)
            let h = Double(rectSize.height)
            let palette = bandPalette(for: style)

            // bias rotation so nothing is perfectly horizontal/vertical
            let globalRotBias = Double.pi * 0.22 // ~39°

            for bandIndex in 0..<bandCount {
                let segments = 160                       // more samples -> smoother curvy ribbons
                var points: [CGPoint] = []

                // base angle per band (varies smoothly) with small RNG jitter
                let baseJitter = (rnd() - 0.5) * 0.18
                let angleBase = Double(bandIndex) * 0.7 + baseJitter

                // larger amplitude for noticeably curvier bands
                let ampBase = (min(w, h) * (0.14 + Double(bandIndex) * 0.02))

                // unique per-band phase so bands don't align
                let phaseBase = seed * 0.37 + Double(bandIndex) * 0.9 + rnd() * 2.0

                for i in 0...segments {
                    let t = Double(i) / Double(segments)    // 0..1
                    let x = t * w

                    // combine multiple sine frequencies and a slow modulation for organic curves
                    let yMiddle = h * 0.5
                    let freq1 = 0.010 + Double(bandIndex) * 0.0018
                    let freq2 = 0.026 + Double(bandIndex) * 0.0022

                    let y =
                        yMiddle
                        + sin(x * freq1 + phaseBase * 0.6) * ampBase * (0.95 + 0.35 * sin(angleBase))
                        + sin(x * freq2 + phaseBase * 0.48 + Double(bandIndex)) * ampBase * 0.36
                        + sin(phaseBase * 0.12 + x * 0.0012) * ampBase * 0.08

                    // rotate around center with a strong bias so ribbons come at an angle
                    let cx = w / 2.0
                    let cy = h / 2.0
                    let dx = x - cx
                    let dy = y - cy

                    // per-band rotation includes global bias and small RNG jitter
                    let rot = angleBase + globalRotBias + (rnd() - 0.5) * 0.12 + sin(phaseBase * 0.18) * 0.36

                    let rx = dx * cos(rot) - dy * sin(rot) + cx
                    let ry = dx * sin(rot) + dy * cos(rot) + cy

                    points.append(CGPoint(x: rx, y: ry))
                }

                guard let first = points.first else { continue }
                let path = UIBezierPath()
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }

                cg.saveGState()
                cg.setLineCap(.round)
                cg.setLineJoin(.round)

                // BROADER ribbons (scale with min dimension); reduce with index so deeper bands taper
                let bw = CGFloat(min(rectSize.width, rectSize.height)) * (0.20 - CGFloat(bandIndex) * 0.01)
                cg.setLineWidth(max(6.0, bw))

                // choose color from palette, slight hue variation via alpha and small RNG
                let baseColor = palette[bandIndex % palette.count]
                let alpha = (style == .dark) ? (0.82 - CGFloat(rnd()) * 0.08) : (0.72 - CGFloat(bandIndex) * 0.06 - CGFloat(rnd()) * 0.06)
                let col = baseColor.withAlphaComponent(alpha)
                cg.setStrokeColor(col.cgColor)

                cg.addPath(path.cgPath)
                cg.strokePath()

                // faint inner highlight for depth
                cg.setLineWidth(max(1.0, bw * 0.26))
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.03).cgColor)
                cg.addPath(path.cgPath)
                cg.strokePath()

                cg.restoreGState()
            }
        }

        // Draw many micro flowers tiled with jitter
        func drawMicroFlowers(in cg: CGContext, rectSize: CGSize, density: CGFloat, seed: Double) {
            let area = rectSize.width * rectSize.height

            // clamp density so it never overwhelms ribbons; choose target count
            let clampedDensity = density.clamped(to: 0.00035...0.0011)
            let target = min(2000, max(140, Int(area * clampedDensity)))

            // compute grid step from target
            let approxStep = max(6, Int(sqrt((rectSize.width * rectSize.height) / CGFloat(target))))
            let step = approxStep

            // richer flower palette
            let paletteFlowers: [UIColor] = [
                UIColor(red: 0.96, green: 0.56, blue: 0.34, alpha: 1.0),
                UIColor(red: 0.98, green: 0.82, blue: 0.35, alpha: 1.0),
                UIColor(red: 0.98, green: 0.39, blue: 0.62, alpha: 1.0),
                UIColor(red: 0.18, green: 0.72, blue: 0.69, alpha: 1.0),
                UIColor(red: 0.56, green: 0.44, blue: 0.92, alpha: 1.0),
                UIColor(red: 0.75, green: 0.45, blue: 0.95, alpha: 1.0),
                UIColor(red: 0.45, green: 0.85, blue: 0.55, alpha: 1.0),
                UIColor(red: 1.00, green: 0.75, blue: 0.45, alpha: 1.0),
                UIColor(red: 0.35, green: 0.85, blue: 0.90, alpha: 1.0)
            ]

            // deterministic RNG from seed
            var rngState = UInt64(bitPattern: Int64(seed.bitPattern ^ 0xC0FFEE))
            func rnd() -> Double {
                rngState &+= 0x9e3779b97f4a7c15
                var z = rngState
                z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
                z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
                return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
            }

            // sampling probability reduces density variability
            let sampleProb = min(0.92, max(0.22, CGFloat(target) / CGFloat((rectSize.width*rectSize.height)/(Double(step*step)+1))))

            var placed: [CGPoint] = []

            for gy in stride(from: 0, to: Int(rectSize.height) + step, by: step) {
                for gx in stride(from: 0, to: Int(rectSize.width) + step, by: step) {
                    if CGFloat(rnd()) > sampleProb { continue } // skip some cells to reduce density
                    let jx = CGFloat((rnd() - 0.5) * Double(step))
                    let jy = CGFloat((rnd() - 0.5) * Double(step))
                    let pos = CGPoint(x: CGFloat(gx) + jx, y: CGFloat(gy) + jy)

                    if pos.x < 0 || pos.x > rectSize.width || pos.y < 0 || pos.y > rectSize.height { continue }

                    let base = CGFloat(step) * (0.28 + CGFloat(rnd()) * 0.78)
                    let flowerSize = max(3.0, min(12.0, base))

                    // spacing check so flowers don't completely stack
                    let minDist = max(6.0, flowerSize * 1.9)
                    var tooClose = false
                    for q in placed {
                        let dx = q.x - pos.x, dy = q.y - pos.y
                        if dx*dx + dy*dy < minDist*minDist { tooClose = true; break }
                    }
                    if tooClose { continue }

                    // mix coordinate hash and RNG for color index to avoid clusters
                    let coordHash = Int(UInt64(gx) &* 73856093 &+ UInt64(gy) &* 19349663)
                    let mix = abs(coordHash ^ Int(rngState & 0xffffffff))
                    let color = paletteFlowers[mix % paletteFlowers.count]
                    let rotation = CGFloat(rnd() * 2.0 * Double.pi)

                    placed.append(pos)
                    drawFlower(in: cg, center: pos, radius: flowerSize * 0.5, color: color, rotation: rotation)
                }
            }
        }

        // subtle grain overlay
        func drawGrain(in cg: CGContext, rectSize: CGSize, style: FloweryStyle) {
            cg.saveGState()
            let alpha: CGFloat = (style == .dark) ? 0.02 : 0.015
            cg.setFillColor(UIColor(white: 1.0, alpha: alpha).cgColor)
            let grainCount = Int((rectSize.width * rectSize.height) / 3000.0)
            for _ in 0..<grainCount {
                let gx = CGFloat(arc4random_uniform(UInt32(rectSize.width)))
                let gy = CGFloat(arc4random_uniform(UInt32(rectSize.height)))
                let r = CGFloat(0.6 + drand48() * 1.6)
                cg.fillEllipse(in: CGRect(x: gx, y: gy, width: r, height: r))
            }
            cg.restoreGState()
        }

        // Final renderer: small closure that calls typed helpers
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)

            // 1) background
            backgroundColor(for: style).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // 2) bands
            drawBands(in: cg, rectSize: size, bandCount: bandCount, seed: seed, style: style)

            // 3) micro flowers
            drawMicroFlowers(in: cg, rectSize: size, density: flowerDensity, seed: seed)

            // 4) grain overlay
            drawGrain(in: cg, rectSize: size, style: style)
        }

        return image
    }
}

// MARK: - Helper utility
fileprivate extension Comparable {
    func clamped(to interval: ClosedRange<Self>) -> Self {
        return min(max(self, interval.lowerBound), interval.upperBound)
    }
}

// MARK: - Thumbnail generator (kept same function name/signature)
public func generateThumbnail(from url: URL) -> UIImage? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    // reasonable size limit
    generator.maximumSize = CGSize(width: 400, height: 400)

    let time = CMTime(seconds: 0.05, preferredTimescale: 600)
    var cgImage: CGImage?
    var actualTime = CMTime.zero
    do {
        cgImage = try generator.copyCGImage(at: time, actualTime: &actualTime)
    } catch {
        print("Thumbnail generation error:", error)
        return nil
    }
    guard let cg = cgImage else { return nil }
    return UIImage(cgImage: cg)
}
