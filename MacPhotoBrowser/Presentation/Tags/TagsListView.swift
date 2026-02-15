//
//  TagsListView.swift
//  MacPhotoBrowser
//

import SwiftUI

struct TagImagesView: View {
    let tag: Tag
    @State private var photos: [PhotoItem] = []
    @State private var isLoading = false
    @State private var selectedPhotoId: UUID?
    @State private var navigationPath = NavigationPath()

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if isLoading {
                    ProgressView("読み込み中...")
                } else if photos.isEmpty {
                    EmptyStateView(
                        icon: "photo.on.rectangle",
                        title: "写真がありません",
                        message: "このタグが付いた写真はありません"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(photos) { photo in
                                PhotoGridItem(photo: photo, isSelected: selectedPhotoId == photo.id)
                                    .onTapGesture(count: 2) {
                                        navigationPath.append(photo)
                                    }
                                    .onTapGesture(count: 1) {
                                        selectedPhotoId = photo.id
                                    }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle(tag.name)
            .navigationDestination(for: PhotoItem.self) { photo in
                DetailView(photoId: photo.id)
            }
        }
        .task {
            await loadPhotos()
        }
    }

    private func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = DependencyContainer.shared.imageRepository
            photos = try await repository.search(byTag: tag.name)
        } catch {
            print("Error loading photos: \(error)")
        }
    }
}
