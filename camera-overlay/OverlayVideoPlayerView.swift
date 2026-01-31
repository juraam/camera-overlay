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
        OverlayVideoPlayerRepresentable(url: url, isPlaying: isPlaying, aspectFit: aspectFit)
            .ignoresSafeArea()
    }
}

private struct OverlayVideoPlayerRepresentable: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let aspectFit: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let playerLayer = AVPlayerLayer(player: context.coordinator.player)
        playerLayer.videoGravity = aspectFit ? .resizeAspect : .resizeAspectFill
        view.layer.addSublayer(playerLayer)
        context.coordinator.playerLayer = playerLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.playerLayer?.frame = uiView.bounds
        context.coordinator.playerLayer?.videoGravity = aspectFit ? .resizeAspect : .resizeAspectFill
        if isPlaying {
            context.coordinator.playFromStart()
        } else {
            context.coordinator.player.pause()
        }
    }

    class Coordinator {
        let player: AVQueuePlayer
        var playerLayer: AVPlayerLayer?
        var looper: AVPlayerLooper?

        init(url: URL) {
            let item = AVPlayerItem(url: url)
            self.player = AVQueuePlayer(playerItem: item)
            self.looper = AVPlayerLooper(player: player, templateItem: item)
        }

        func playFromStart() {
            player.seek(to: .zero)
            player.play()
        }
    }
}
