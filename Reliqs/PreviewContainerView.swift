//
//  PreviewContainerView.swift
//  Memori
//
//  Created by Abhinav Garapati on 07/12/25.
//


//
//  Memori
//
//  Created by Abhinav Garapati on 30/08/25.
//
//  PreviewContainerView.swift

import SwiftUI
import AVFoundation

final class PreviewContainerView: UIView {
    let previewLayer: AVCaptureVideoPreviewLayer
    init(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        super.init(frame: .zero)
        backgroundColor = .clear // ← helps you see if the view is on screen
        layer.addSublayer(previewLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

struct CameraPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewContainerView {
        let v = PreviewContainerView(previewLayer: CameraManager.shared.previewLayer)
        
        // ✅ Default to black so no purple flash
        v.backgroundColor = .clear
        CameraManager.shared.previewLayer.backgroundColor = UIColor.black.cgColor
        
        // Pinch gesture
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        v.addGestureRecognizer(pinch)
        
        // Tap gesture
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        v.addGestureRecognizer(tap)
        
        return v
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    final class Coordinator: NSObject {
        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            if g.state == .changed {
                if let device = CameraManager.shared.videoInput?.device {
                    let zoomFactor = max(1.0,
                        min(device.activeFormat.videoMaxZoomFactor,
                            device.videoZoomFactor * g.scale))
                    do {
                        try device.lockForConfiguration()
                        device.videoZoomFactor = zoomFactor
                        device.unlockForConfiguration()
                    } catch { print("Zoom error:", error) }
                }
                g.scale = 1.0
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            let v = g.view!
            let pt = g.location(in: v)
            let conv = CameraManager.shared.previewLayer.captureDevicePointConverted(fromLayerPoint: pt)
            if let device = CameraManager.shared.videoInput?.device {
                do {
                    try device.lockForConfiguration()
                    if device.isFocusPointOfInterestSupported {
                        device.focusPointOfInterest = conv
                        device.focusMode = .autoFocus
                    }
                    if device.isExposurePointOfInterestSupported {
                        device.exposurePointOfInterest = conv
                        device.exposureMode = .autoExpose
                    }
                    device.unlockForConfiguration()
                } catch { print("Focus error:", error) }
            }
        }
    }
}
