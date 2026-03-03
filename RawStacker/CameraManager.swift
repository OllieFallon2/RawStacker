import AVFoundation
import Photos
import Combine
import UIKit
import ImageIO
import UniformTypeIdentifiers

class CameraManager: NSObject, ObservableObject {
    // Services
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let stacker = ImageStacker()
    
    // UI State
    @Published var isRawSupported: Bool = false
    @Published var isStackingEnabled: Bool = false
    @Published var isProcessing: Bool = false
    @Published var stackCount: Int = 5
    @Published var saveAsJPEG: Bool = false
    
    // Manual Exposure State
    @Published var isManualMode: Bool = false
    @Published var currentISO: Float = 100
    @Published var currentShutterSpeed: Double = 0.02
    @Published var minISO: Float = 0
    @Published var maxISO: Float = 0
    @Published var minDuration: Double = 0.0001
    @Published var maxDuration: Double = 1.0
    
    private var burstCount = 0
    private var tempFolderURL: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("RawBurst")
    }
    
    override init() {
        super.init()
        requestPermissions()
        setupSession()
    }
    
    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
    }
    
    // MARK: - Hardware Setup
    private func setupSession() {
        sessionQueue.async { self.configureCameraHardware() }
    }

    private func configureCameraHardware() {
        self.session.beginConfiguration()
        self.session.sessionPreset = .photo
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            self.session.commitConfiguration()
            return
        }
        
        if self.session.canAddInput(videoDeviceInput) { self.session.addInput(videoDeviceInput) }
        if self.session.canAddOutput(self.photoOutput) {
            self.session.addOutput(self.photoOutput)
            if #available(iOS 16.0, *) {
                let dims = videoDevice.activeFormat.supportedMaxPhotoDimensions
                if let maxDim = dims.last { self.photoOutput.maxPhotoDimensions = maxDim }
            }
        }
        self.session.commitConfiguration()
        
        DispatchQueue.main.async {
            self.minISO = videoDevice.activeFormat.minISO
            self.maxISO = videoDevice.activeFormat.maxISO
            self.minDuration = videoDevice.activeFormat.minExposureDuration.seconds
            self.maxDuration = videoDevice.activeFormat.maxExposureDuration.seconds
            self.currentISO = videoDevice.iso
            self.currentShutterSpeed = videoDevice.exposureDuration.seconds
            self.isRawSupported = !self.photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        }
    }

    func applyManualSettings() {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if self.isManualMode {
                    let safeISO = max(self.minISO, min(self.currentISO, self.maxISO))
                    let safeDur = max(self.minDuration, min(self.currentShutterSpeed, self.maxDuration))
                    let duration = CMTime(seconds: safeDur, preferredTimescale: 1000000)
                    device.setExposureModeCustom(duration: duration, iso: safeISO, completionHandler: nil)
                } else {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { print("Exposure Error: \(error)") }
        }
    }

    func handleCapture() {
        if isStackingEnabled {
            prepareTempFolder()
            burstCount = 0
            captureBurst(count: stackCount)
        } else {
            captureRawPhoto()
        }
    }

    private func captureRawPhoto() {
        sessionQueue.async { self.executeHardwareCapture() }
    }

    private func executeHardwareCapture() {
        guard let rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first else {
            print("Hardware reports RAW not supported")
            return
        }
        
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
        if #available(iOS 16.0, *) {
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
        }
        self.photoOutput.capturePhoto(with: settings, delegate: self)
        print("Shutter Signal Sent!")
    }

    private func captureBurst(count: Int) {
        var shotsTaken = 0
        Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.captureRawPhoto()
            shotsTaken += 1
            if shotsTaken >= count { timer.invalidate() }
        }
    }

    private func processStack() {
        DispatchQueue.main.async { self.isProcessing = true }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let urls = (try? FileManager.default.contentsOfDirectory(at: self.tempFolderURL, includingPropertiesForKeys: nil)) ?? []
            self.stacker.stackImages(urls: urls) { [weak self] finalImage in
                guard let self = self, let final = finalImage else {
                    DispatchQueue.main.async { self?.isProcessing = false }; return
                }
                let context = CIContext(options: [.workingColorSpace: NSNull()])
                let orientation = CGImagePropertyOrientation(UIDevice.current.orientation)
                if let cgImage = context.createCGImage(final, from: final.extent) {
                    let data: Data?
                    if self.saveAsJPEG {
                        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: self.uiOrientationFrom(orientation))
                        data = uiImage.jpegData(compressionQuality: 0.95)
                    } else {
                        data = self.convertBufferToTIFF(cgImage, orientation: orientation)
                    }
                    if let finalData = data {
                        PHPhotoLibrary.shared().performChanges({
                            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: finalData, options: nil)
                        }) { success, _ in
                            DispatchQueue.main.async {
                                self.isProcessing = false
                                self.prepareTempFolder()
                            }
                        }
                    }
                }
            }
        }
    }

    private func convertBufferToTIFF(_ cgImage: CGImage, orientation: CGImagePropertyOrientation) -> Data {
        let mutableData = NSMutableData()
        if let dest = CGImageDestinationCreateWithData(mutableData, UTType.tiff.identifier as CFString, 1, nil) {
            let options = [kCGImagePropertyOrientation as String: orientation.rawValue]
            CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
            CGImageDestinationFinalize(dest)
        }
        return mutableData as Data
    }

    private func uiOrientationFrom(_ orientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch orientation { case .up: return .up; case .down: return .down; case .left: return .left; case .right: return .right; default: return .up }
    }

    func startSession() {
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
    }
    
    private func prepareTempFolder() {
        try? FileManager.default.removeItem(at: tempFolderURL)
        try? FileManager.default.createDirectory(at: tempFolderURL, withIntermediateDirectories: true)
    }

    var estimatedSizeMB: String {
        let base = Double(stackCount) * 25.0
        return String(format: "%.0f MB", base + (saveAsJPEG ? 5.0 : 50.0))
    }
    
    var estimatedTimeSecconds: String {
        return String(format: "%.1f sec", (Double(stackCount) * 0.7) + (Double(stackCount) * 1.2))
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        Task { @MainActor in
            if self.isStackingEnabled {
                let fileURL = self.tempFolderURL.appendingPathComponent("\(UUID().uuidString).dng")
                try? data.write(to: fileURL)
                self.burstCount += 1
                if self.burstCount >= self.stackCount {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.processStack() }
                }
            } else {
                PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIDeviceOrientation) {
        switch uiOrientation { case .portrait: self = .right; case .portraitUpsideDown: self = .left; case .landscapeLeft: self = .up; case .landscapeRight: self = .down; default: self = .right }
    }
}

