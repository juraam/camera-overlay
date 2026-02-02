//
//  OverlayVideoPlayerView.swift
//  camera-overlay
//

import SwiftUI
import AVFoundation

struct OverlayVideoPlayerView: View {
    let url: URL
    let isPlaying: Bool
    var aspectFit: Bool = false

    var body: some View {
        if isPlaying {
            OverlayVideoPlayerRepresentable(url: url, isPlaying: true, aspectFit: aspectFit)
                .id(url)
                .ignoresSafeArea()
        } else {
            VideoThumbnailView(url: url)
                .ignoresSafeArea()
        }
    }
}

private struct OverlayVideoPlayerRepresentable: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let aspectFit: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .clear
        let playerLayer = AVPlayerLayer(player: context.coordinator.player)
        playerLayer.videoGravity = aspectFit ? .resizeAspect : .resizeAspectFill
        view.layer.addSublayer(playerLayer)
        context.coordinator.playerLayer = playerLayer
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        context.coordinator.playerLayer?.frame = uiView.bounds
        context.coordinator.playerLayer?.videoGravity = aspectFit ? .resizeAspect : .resizeAspectFill
        context.coordinator.playFromStart()
    }

    class Coordinator: NSObject {
        let player: AVQueuePlayer
        var playerLayer: AVPlayerLayer?
        var looper: AVPlayerLooper?
        var statusObserver: NSKeyValueObservation?

        init(url: URL) {
            let item = AVPlayerItem(url: url)
            self.player = AVQueuePlayer(playerItem: item)
            self.looper = AVPlayerLooper(player: player, templateItem: item)
            super.init()
            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .readyToPlay else { return }
                Task { @MainActor in
                    self?.player.seek(to: .zero)
                    self?.player.play()
                }
            }
        }

        func playFromStart() {
            player.seek(to: .zero)
            if player.currentItem?.status == .readyToPlay {
                player.play()
            }
        }
    }
}

private final class PlayerContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.first?.frame = bounds
    }
}
