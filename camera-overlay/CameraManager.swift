//
//  CameraManager.swift
//  supplimenttracker
//
//  Created by Moshkov Yuriy on 13.07.2025.
//

import AVFoundation
import AudioToolbox
import CoreImage
import UIKit
import Combine

class CameraManager: NSObject, ObservableObject {

    private let captureSession = AVCaptureSession()
    private var deviceInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var currentCameraPosition: AVCaptureDevice.Position = .front

    private var sessionQueue = DispatchQueue(label: "video.preview.session")

    private var addToPreviewStream: ((CGImage) -> Void)?
    private var photoCaptureCompletion: ((UIImage?) -> Void)?

    lazy var previewStream: AsyncStream<CGImage> = {
        AsyncStream { continuation in
            addToPreviewStream = { cgImage in
                continuation.yield(cgImage)
            }
        }
    }()

    @Published var isAuthorized: Bool = false
    @Published var isTorchOn: Bool = false
    @Published var isTorchAvailable: Bool = false
    @Published var cameraPosition: AVCaptureDevice.Position = .front
    @Published var isRecording: Bool = false

    private var videoRecordCompletion: ((URL?) -> Void)?

    var isAuthorizedWithRequest: Bool {
        get async {
            let status = AVCaptureDevice.authorizationStatus(for: .video)

            // Determine if the user previously authorized camera access.
            var isAuthorized = status == .authorized
            Task { @MainActor in
                self.isAuthorized = status == .authorized
            }

            // If the system hasn't determined the user's authorization status,
            // explicitly prompt them for approval.
            if status == .notDetermined {
                isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
                Task { @MainActor in
                    self.isAuthorized = isAuthorized
                }
            }

            return isAuthorized
        }
    }

    override init() {
        super.init()

        Task {
            await configureSession()
            await startSession()
            await updateTorchAvailability()
        }

    }

    private func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func configureSession() async {
        guard await isAuthorizedWithRequest,
              let device = device(for: currentCameraPosition),
              let deviceInput = try? AVCaptureDeviceInput(device: device)
        else { return }

        captureSession.beginConfiguration()

        defer {
            self.captureSession.commitConfiguration()
        }

        if let existingInput = self.deviceInput {
            captureSession.removeInput(existingInput)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }

        let videoOutput = AVCaptureVideoDataOutput()
        let photoOutput = AVCapturePhotoOutput()
        let movieOutput = AVCaptureMovieFileOutput()

        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        guard captureSession.canAddInput(deviceInput) else { return }
        guard captureSession.canAddOutput(videoOutput) else { return }
        guard captureSession.canAddOutput(photoOutput) else { return }
        guard captureSession.canAddOutput(movieOutput) else { return }

        captureSession.addInput(deviceInput)
        captureSession.addOutput(videoOutput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(movieOutput)

        self.deviceInput = deviceInput
        self.photoOutput = photoOutput
        self.movieOutput = movieOutput

        videoOutput.connection(with: .video)?.videoRotationAngle = 90

        Task { @MainActor in
            self.cameraPosition = currentCameraPosition
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = self.currentCameraPosition == .front ? .back : .front
            self.currentCameraPosition = newPosition
            Task {
                await self.configureSession()
                await self.startSession()
                await self.updateTorchAvailability()
            }
        }
    }

    func startRecording() async -> URL? {
        guard let movieOutput = movieOutput else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        return await withCheckedContinuation { continuation in
            videoRecordCompletion = { url in
                continuation.resume(returning: url)
            }
            movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        }
    }

    func stopRecording() {
        movieOutput?.stopRecording()
    }

    func capturePhoto() async -> UIImage? {
        guard let photoOutput = photoOutput else { return nil }
        
        return await withCheckedContinuation { continuation in
            photoCaptureCompletion = { image in
                continuation.resume(returning: image)
            }
            
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Torch Control
    
    func toggleTorch() {
        if isTorchOn {
            disableTorch()
        } else {
            enableTorch()
        }
    }
    
    func enableTorch() {
        guard let device = deviceInput?.device,
              device.hasTorch,
              device.isTorchAvailable else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = .on
            device.unlockForConfiguration()
            
            Task { @MainActor in
                self.isTorchOn = true
            }
        } catch {
            print("Error enabling torch: \(error)")
        }
    }
    
    func disableTorch() {
        guard let device = deviceInput?.device,
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
            
            Task { @MainActor in
                self.isTorchOn = false
            }
        } catch {
            print("Error disabling torch: \(error)")
        }
    }
    
    private func updateTorchAvailability() async {
        guard let device = deviceInput?.device else { return }
        
        Task { @MainActor in
            self.isTorchAvailable = device.hasTorch && device.isTorchAvailable
        }
    }

    private func startSession() async {
        guard await isAuthorizedWithRequest else { return }
        captureSession.startRunning()
    }

    private func rotate(by angle: CGFloat, from connection: AVCaptureConnection) {
        guard connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let currentFrame = sampleBuffer.cgImage else {
            print("Can't translate to CGImage")
            return
        }
        addToPreviewStream?(currentFrame)
    }

}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        AudioServicesPlaySystemSound(1117)
        Task { @MainActor in
            self.isRecording = true
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        AudioServicesPlaySystemSound(1118)
        Task { @MainActor in
            self.isRecording = false
        }
        videoRecordCompletion?(error == nil ? outputFileURL : nil)
        videoRecordCompletion = nil
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            photoCaptureCompletion?(nil)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("Could not create image from photo data")
            photoCaptureCompletion?(nil)
            return
        }
        
        photoCaptureCompletion?(image)
    }
}


extension CMSampleBuffer {
    var cgImage: CGImage? {
        let pixelBuffer: CVPixelBuffer? = CMSampleBufferGetImageBuffer(self)
        guard let imagePixelBuffer = pixelBuffer else { return nil }
        return CIImage(cvPixelBuffer: imagePixelBuffer).cgImage
    }
}

extension CIImage {
    var cgImage: CGImage? {
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
        return cgImage
    }
}
