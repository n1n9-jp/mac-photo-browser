//
//  TagRepositoryProtocol.swift
//  MacPhotoBrowser
//

import Foundation

protocol TagRepositoryProtocol {
    func fetchAll() async throws -> [Tag]
    func fetchAllWithImageCount() async throws -> [TagWithCount]
    func fetch(byId id: UUID) async throws -> Tag?
    func fetch(byName name: String) async throws -> Tag?
    func save(_ tag: Tag) async throws
    func delete(_ tag: Tag) async throws
    func addTag(_ tag: Tag, to imageId: UUID) async throws
    func removeTag(_ tag: Tag, from imageId: UUID) async throws
    /// 画像が1枚も紐づいていない孤立タグを一括削除
    func deleteOrphanedTags() async throws
}

struct TagWithCount: Identifiable {
    let tag: Tag
    let imageCount: Int

    var id: UUID { tag.id }
}
