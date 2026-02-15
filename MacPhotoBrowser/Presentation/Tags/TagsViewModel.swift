//
//  TagsViewModel.swift
//  MacPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class TagsViewModel: ObservableObject {
    @Published private(set) var tagsWithCount: [TagWithCount] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var showingError = false

    private let tagRepository: TagRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    init(tagRepository: TagRepositoryProtocol) {
        self.tagRepository = tagRepository

        NotificationCenter.default.publisher(for: .tagsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadTags()
                }
            }
            .store(in: &cancellables)
    }

    func loadTags() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tagsWithCount = try await tagRepository.fetchAllWithImageCount()
        } catch {
            self.error = error
            showingError = true
        }
    }

    func deleteTag(_ tag: Tag) async {
        do {
            try await tagRepository.delete(tag)
            tagsWithCount.removeAll { $0.tag.id == tag.id }
        } catch {
            self.error = error
            showingError = true
        }
    }
}
