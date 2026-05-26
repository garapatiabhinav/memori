//
//  CameraManager.swift
//  Memori
//
//  Created by Abhinav Garapati on 07/12/25.
//

//
//  CameraManager.swift
//  Memori
//
//  Created by Abhinav Garapati on 07/12/25.
//

//
//  CameraManager.swift
//  Memori
//
//  Updated for iOS 18.5
//

import AVFoundation
import UIKit
import Combine



final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    // Session
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "cam.session.queue")

    // Preview
    let previewLayer = AVCaptureVideoPreviewLayer()

    // I/O
    private(set) var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput() // diagnostics only
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    // new in CameraManager.swift (place near other @Published properties)
    enum PermissionType {
        case none, camera, microphone, both
    }

    @Published var permissionDeniedFor: PermissionType = .none

    // Diagnostics / UI
    @Published var status: String = "Booting…"
    @Published var isRunning: Bool = false
    @Published var hasPermission: Bool = false
    @Published var frameCount: Int = 0
    @Published var lastCaptureAt: Date?

    // Last captures
    @Published var lastPhoto: UIImage?
    @Published var lastVideoURL: URL?

    override init() {
        super.init()
        previewLayer.videoGravity = .resizeAspectFill
        NotificationCenter.default.addObserver(self, selector: #selector(runtimeError(_:)), name: AVCaptureSession.runtimeErrorNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)), name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(interruptionEnded(_:)), name: AVCaptureSession.interruptionEndedNotification, object: session)
    }

    // MARK: Public
    func start() {
        setStatus("Starting…")
        sessionQueue.async {
            // Ensure permissions first (this runs callbacks on main queue)
            DispatchQueue.main.async {
                self.ensureVideoAndAudioPermissions { granted in
                    guard granted else {
                        // do not attempt to configure or run session when denied
                        return
                    }
                    // proceed on session queue as before
                    self.sessionQueue.async {
                        self.configureIfNeeded()
                        guard !self.session.isRunning else {
                            self.setStatus("Session already running")
                            return
                        }
                        self.session.startRunning()
                        DispatchQueue.main.async {
                            self.isRunning = self.session.isRunning
                            self.setStatus(self.session.isRunning ? "Running ✅" : "Failed to run ❌")
                        }
                    }
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                self.setStatus("Stopped")
            }
        }
    }

    // MARK: - Photo Capture
    func capturePhoto() {
        sessionQueue.async {
            guard self.isRunning else { return }
            let settings = AVCapturePhotoSettings()
            if let c = self.previewLayer.connection {
                c.videoRotationAngle = 90
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Video Recording
    func startRecording() {
        sessionQueue.async {
            guard self.isRunning, !self.movieOutput.isRecording else { return }

            // orientation
            if let conn = self.movieOutput.connection(with: .video) {
                conn.videoRotationAngle = 90
            }

            // output file URL
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".mov")

            self.movieOutput.startRecording(to: fileURL, recordingDelegate: self)
            self.setStatus("Recording 🎥")
        }
    }

    func stopRecording(completion: ((URL?) -> Void)? = nil) {
        sessionQueue.async {
            guard self.movieOutput.isRecording else { completion?(nil); return }
            self.movieOutput.stopRecording()

            // Capture completion callback when finished
            self.videoCompletion = completion
        }
    }

    private var videoCompletion: ((URL?) -> Void)?

    // MARK: - Flip camera
    func flipCamera() {
        sessionQueue.async {
            guard let currentInput = self.videoInput else { return }
            self.session.beginConfiguration()
            self.session.removeInput(currentInput)

            let newPos: AVCaptureDevice.Position = (currentInput.device.position == .back) ? .front : .back
            if let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPos),
               let newInput = try? AVCaptureDeviceInput(device: newDevice),
               self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
            }
            self.session.commitConfiguration()
        }
    }

    // MARK: - Pinch zoom
    func setZoom(_ factor: CGFloat) {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let zoom = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
        } catch { print("Zoom error:", error) }
    }

    // MARK: - Tap focus + expose
    func focus(at point: CGPoint) {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch { print("Focus error:", error) }
    }
    // new helper in CameraManager.swift
    /// Ensure camera + microphone permission. Publishes permissionDeniedFor when any permission is explicitly denied.
    /// Calls completion(true) when both granted.
    func ensureVideoAndAudioPermissions(completion: @escaping (Bool) -> Void) {
        // We'll request both (non-blocking) and return when both decided
        let group = DispatchGroup()

        var cameraGranted = false
        var micGranted = false

        group.enter()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraGranted = true
            group.leave()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cameraGranted = granted; group.leave() }
            }
        default:
            // .denied or .restricted
            cameraGranted = false
            group.leave()
        }

        group.enter()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micGranted = true
            group.leave()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { micGranted = granted; group.leave() }
            }
        default:
            micGranted = false
            group.leave()
        }

        group.notify(queue: .main) {
            // Set flags / status for UI
            self.hasPermission = cameraGranted
            if cameraGranted && micGranted {
                self.permissionDeniedFor = .none
                completion(true)
            } else {
                // choose best reason to show to user
                if !cameraGranted && !micGranted {
                    self.permissionDeniedFor = .both
                    self.setStatus("Camera + Microphone permission denied ❌")
                } else if !cameraGranted {
                    self.permissionDeniedFor = .camera
                    self.setStatus("Camera permission denied ❌")
                } else {
                    self.permissionDeniedFor = .microphone
                    self.setStatus("Microphone permission denied ❌")
                }
                completion(false)
            }
        }
    }

    // MARK: - Configure
    private func configureIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.hasPermission = true }
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.hasPermission = granted }
                sem.signal()
            }
            sem.wait()
            if !hasPermission { setStatus("No permission ❌"); return }
        default:
            DispatchQueue.main.async {
                self.hasPermission = false
                self.setStatus("Permission denied ❌")
            }
            return
        }

        if !session.inputs.isEmpty { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        // Camera selection
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        guard let device = discovery.devices.first ??
                AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            setStatus("No back camera ❌")
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            setStatus("Cannot add input ❌")
            return
        }
        session.addInput(input)
        self.videoInput = input

        // Outputs
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cam.video.output"))

        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

        // Preview
        previewLayer.session = session
        if let conn = previewLayer.connection {
            conn.videoRotationAngle = 90
        }

        session.commitConfiguration()
        setStatus("Configured ✅")
    }

    private func setStatus(_ s: String) {
        DispatchQueue.main.async { self.status = s }
        print("[CameraManager] \(s)")
    }

    @objc private func runtimeError(_ note: Notification) {
        if let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            print("[CameraManager] Runtime error:", err)
            setStatus("Runtime error ❌")
        }
    }
    @objc private func interrupted(_ note: Notification) {
        print("[CameraManager] Interrupted:", note.userInfo ?? [:])
        setStatus("Interrupted ⏸")
    }
    @objc private func interruptionEnded(_ note: Notification) {
        print("[CameraManager] Interruption ended")
        setStatus("Resumed ▶︎")
    }
}

// MARK: - Delegates
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        DispatchQueue.main.async { self.frameCount += 1 }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        DispatchQueue.main.async { self.lastCaptureAt = Date() }
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let img = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.lastPhoto = img }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async { self.lastCaptureAt = Date() }
        if error == nil {
            DispatchQueue.main.async {
                self.lastVideoURL = outputFileURL
                self.videoCompletion?(outputFileURL)
                self.videoCompletion = nil
            }
        } else {
            print("Video recording error: \(String(describing: error))")
            DispatchQueue.main.async {
                self.videoCompletion?(nil)
                self.videoCompletion = nil
            }
        }
    }
}
