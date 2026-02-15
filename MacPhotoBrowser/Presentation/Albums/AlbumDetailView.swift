//
//  AlbumDetailView.swift
//  MacPhotoBrowser
//

import SwiftUI

struct AlbumDetailView: View {
    @StateObject private var viewModel: AlbumDetailViewModel
    @State private var selectedPhotoId: UUID?
    @State private var navigationPath = NavigationPath()

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    init(album: Album) {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeAlbumDetailViewModel(album: album))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.photos.isEmpty {
                    EmptyStateView(
                        icon: "photo.on.rectangle",
                        title: "写真がありません",
                        message: "このアルバムにはまだ写真がありません"
                    )
                } else {
                    photoGrid
                }
            }
            .navigationTitle(viewModel.album.name)
            .navigationDestination(for: PhotoItem.self) { photo in
                DetailView(photoId: photo.id)
            }
        }
        .task {
            await viewModel.loadPhotos()
        }
        .refreshable {
            await viewModel.loadPhotos()
        }
        .alert("エラー", isPresented: $viewModel.showingError) {
            Button("OK") {}
        } message: {
            Text(viewModel.error?.localizedDescription ?? "不明なエラー")
        }
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.photos) { photo in
                    PhotoGridItem(photo: photo, isSelected: selectedPhotoId == photo.id)
                        .onTapGesture(count: 2) {
                            navigationPath.append(photo)
                        }
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded {
                                selectedPhotoId = photo.id
                            }
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.removeImage(photo)
                                }
                            } label: {
                                Label("アルバムから削除", systemImage: "minus.circle")
                            }
                        }
                }
            }
            .padding(4)
        }
    }
}
