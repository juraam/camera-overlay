//
//  AspectRatioImage.swift
//  supplimenttracker
//
//  Created by Moshkov Yuriy on 14.07.2025.
//

import SwiftUI
import UIKit

struct AspectRatioImage: View {
    enum ImageSource {
        case image(Image)
    }

    let image: ImageSource
    let aspectRatio: CGFloat?
    var maxWidth: CGFloat?
    var maxHeight: CGFloat?
    var width: CGFloat?
    var contentMode: SwiftUI.ContentMode = .fill

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(width: width)
            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
            .overlay(
                imageView
                    .aspectRatio(contentMode: contentMode)
            )
            .clipped()
    }

    @ViewBuilder
    var imageView: some View {
        switch image {
        case .image(let image):
            image
                .resizable()
        }
    }
}

#Preview {
    AspectRatioImage(
        image: .image(Image(systemName: "photo")),
        aspectRatio: 1,
        width: 100
    )
    .padding()
}
