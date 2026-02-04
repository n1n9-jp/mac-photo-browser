//
//  BookInfoRepositoryProtocol.swift
//  iOSPhotoBrowser
//

import Foundation

protocol BookInfoRepositoryProtocol {
    func save(_ bookInfo: BookInfo, for imageId: UUID) async throws
    func fetch(for imageId: UUID) async throws -> BookInfo?
    func update(_ bookInfo: BookInfo) async throws
    func delete(for imageId: UUID) async throws
}
