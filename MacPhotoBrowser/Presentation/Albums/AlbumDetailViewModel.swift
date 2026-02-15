//
//  AlbumDetailViewModel.swift
//  MacPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    @Published private(set) var photos: [PhotoItem] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var showingError = false

    let album: Album
    private let albumRepository: AlbumRepositoryProtocol
    private let imageRepository: ImageRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    init(
        album: Album,
        albumRepository: AlbumRepositoryProtocol,
        imageRepository: ImageRepositoryProtocol
    ) {
        self.album = album
        self.albumRepository = albumRepository
        self.imageRepository = imageRepository

        NotificationCenter.default.publisher(for: .albumsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadPhotos()
                }
            }
            .store(in: &cancellables)
    }

    func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }

        do {
            photos = try await imageRepository.fetchImages(inAlbum: album.id)
        } catch {
            self.error = error
            showingError = true
        }
    }

    func removeImage(_ photo: PhotoItem) async {
        do {
            try await albumRepository.removeImage(photo.id, from: album.id)
            photos.removeAll { $0.id == photo.id }
            NotificationCenter.default.post(name: .albumsDidChange, object: nil)
        } catch {
            self.error = error
            showingError = true
        }
    }
}
