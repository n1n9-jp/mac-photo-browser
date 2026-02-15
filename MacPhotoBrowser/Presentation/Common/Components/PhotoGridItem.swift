//
//  PhotoGridItem.swift
//  MacPhotoBrowser
//

import SwiftUI

struct PhotoGridItem: View {
    let photo: PhotoItem
    var isSelected: Bool = false
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: 4)
        .draggable(photo.id.uuidString)
        .task {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        // Check cache first
        if let cached = ThumbnailCache.shared.get(for: photo.id) {
            thumbnail = cached
            return
        }

        // Load from disk
        if let thumbnailPath = photo.thumbnailPath,
           let image = FileStorageManager.shared.loadThumbnail(fileName: thumbnailPath) {
            thumbnail = image
            ThumbnailCache.shared.set(image, for: photo.id)
        }
    }
}
