//
//  BookInfo.swift
//  iOSPhotoBrowser
//

import Foundation

struct BookInfo: Identifiable, Hashable {
    let id: UUID
    let isbn: String
    var title: String?
    var author: String?
    var publisher: String?
    var publishedDate: String?
    var coverUrl: String?
    var category: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        isbn: String,
        title: String? = nil,
        author: String? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        coverUrl: String? = nil,
        category: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.isbn = isbn
        self.title = title
        self.author = author
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.coverUrl = coverUrl
        self.category = category
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
