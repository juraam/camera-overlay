//
//  CameraView.swift
//  supplimenttracker
//
//  Created by Moshkov Yuriy on 12.07.2025.
//

import SwiftUI
import AVFoundation
import PhotosUI

enum OverlayType {
    case image
    case video
}

enum CaptureMode {
    case photo
    case video
}

extension CGFloat {
    static func gridSteps(_ steps: Int) -> CGFloat {
        CGFloat(steps) * 4
    }
}

struct CameraView: View {
    var isMock = false
    @StateObject var cameraManager = CameraManager()

    @State var currentFrame: CGImage?
    @State var isCapturing = false
    @State var capturedImage: UIImage?
    @State var isLoading = false

    @State private var overlayType: OverlayType = .image
    @State private var overlayOpacity: Double = 30
    @State private var isOverlayOnCamera: Bool = true
    @State private var referenceImage: UIImage?
    @State private var referenceVideoURL: URL?
    @State private var captureMode: CaptureMode = .photo
    @State private var delaySeconds: Int = 0
    @State private var photoLibraryItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black
            cameraStream
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            VStack(spacing: 0) {
                topPanel
                Spacer()
                bottomPanel
                    .padding(.horizontal, .gridSteps(4))
            }
        }
        .onAppear {
            Task {
                for await image in cameraManager.previewStream {
                    Task { @MainActor in
                        currentFrame = image
                    }
                }
            }
        }
    }

    var topPanel: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(isOverlayOnCamera ? "Over camera" : "Right top")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                Toggle("", isOn: $isOverlayOnCamera)
                    .labelsHidden()
            }
            Spacer()
            HStack(spacing: 8) {
                overlayThumbnail
                if isOverlayOnCamera {
                    Slider(value: $overlayOpacity, in: 0...100, step: 1)
                        .frame(maxWidth: 80)
                    Text("\(Int(overlayOpacity))%")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .frame(width: 36, alignment: .leading)
                }
            }
        }
        .padding(.top, .gridSteps(2))
        .padding(.bottom, .gridSteps(3))
        .padding(.horizontal, .gridSteps(4))
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var overlayThumbnail: some View {
        Group {
            if overlayType == .image, let referenceImage {
                Image(uiImage: referenceImage)
                    .resizable()
                    .scaledToFit()
            } else if overlayType == .video, let referenceVideoURL {
                OverlayVideoPlayerView(url: referenceVideoURL, isPlaying: true, aspectFit: true)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.3))
                    .overlay(
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(Color.secondary)
                    )
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .frame(width: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var bottomPanel: some View {
        VStack(spacing: .gridSteps(2)) {
            delayButton
            HStack(spacing: 0) {
                PhotosPicker(
                    selection: $photoLibraryItem,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.white)
                }
                .onChange(of: photoLibraryItem) { _, newValue in
                    Task {
                        await loadPhotoLibraryItem(newValue)
                    }
                }
                Spacer()
                captureButton
                Spacer()
                Button(action: { cameraManager.switchCamera() }) {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.white)
                }
            }
            captureModeSwitcher
        }
    }

    private var delayButton: some View {
        Button(action: {
            switch delaySeconds {
            case 0: delaySeconds = 3
            case 3: delaySeconds = 5
            default: delaySeconds = 0
            }
        }) {
            Text("\(delaySeconds)")
                .font(.headline)
                .foregroundStyle(Color.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))
        }
    }

    private var captureModeSwitcher: some View {
        Picker("", selection: $captureMode) {
            Text("Photo").tag(CaptureMode.photo)
            Text("Video").tag(CaptureMode.video)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 180)
        .onAppear {
            UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        }
    }

    var cameraStream: some View {
        ZStack {
            GeometryReader { geometry in
                if let currentFrame {
                    Image(decorative: currentFrame, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width,
                               height: geometry.size.height)
                        .clipped()
                } else {
                    Color.black
                }
            }
            if isOverlayOnCamera && overlayOpacity > 0 {
                overlayContent
            }
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        Group {
            if overlayType == .image, let referenceImage {
                Image(uiImage: referenceImage)
                    .resizable()
                    .scaledToFit()
            } else if overlayType == .video, let referenceVideoURL {
                OverlayVideoPlayerView(url: referenceVideoURL, isPlaying: cameraManager.isRecording, aspectFit: true)
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(overlayOpacity / 100)
        .allowsHitTesting(false)
    }

    var captureButton: some View {
        let isRecordingActive = (captureMode == .photo && isCapturing) || cameraManager.isRecording
        return Button(action: performCapture) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(captureMode == .video ? Color.red : Color.white)
                    .frame(width: 70, height: 70)
                if isCapturing && captureMode == .photo {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.accentColor))
                        .scaleEffect(1.5)
                }
            }
        }
        .disabled((captureMode == .photo && isCapturing) || !cameraManager.isAuthorized)
        .scaleEffect(isRecordingActive ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isRecordingActive)
    }

    private func performCapture() {
        if captureMode == .video {
            if cameraManager.isRecording {
                cameraManager.stopRecording()
            } else {
                runWithDelay {
                    startVideoRecording()
                }
            }
            return
        }
        runWithDelay {
            capturePhoto()
        }
    }

    private func runWithDelay(action: @escaping () -> Void) {
        guard delaySeconds > 0 else {
            action()
            return
        }
        isCapturing = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            await MainActor.run {
                isCapturing = false
                action()
            }
        }
    }

    private func capturePhoto() {
        isCapturing = true
        Task {
            let image = await cameraManager.capturePhoto()
            await MainActor.run {
                isCapturing = false
                capturedImage = image
            }
            if let image {
                _ = await PhotoLibrarySaver.saveImage(image)
            }
        }
    }

    private func startVideoRecording() {
        Task {
            if let url = await cameraManager.startRecording() {
                _ = await PhotoLibrarySaver.saveVideo(url: url)
            }
        }
    }

    private func loadPhotoLibraryItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await MainActor.run {
                referenceImage = image
                referenceVideoURL = nil
                overlayType = .image
                photoLibraryItem = nil
            }
            return
        }
        if let video = try? await item.loadTransferable(type: VideoTransferable.self) {
            await MainActor.run {
                referenceVideoURL = video.url
                referenceImage = nil
                overlayType = .video
                photoLibraryItem = nil
            }
        }
    }
}

extension CameraView {
    enum Output {
        case showLoading(UIImage)
        case onClose
    }
}

// Safe array subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + (received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension))
            try FileManager.default.copyItem(at: received.file, to: temp)
            return Self(url: temp)
        }
    }
}

#Preview {
    CameraView(
        isMock: true
    )
}
