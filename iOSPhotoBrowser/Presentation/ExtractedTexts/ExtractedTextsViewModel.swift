//
//  ExtractedTextsViewModel.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

@MainActor
final class ExtractedTextsViewModel: ObservableObject {
    @Published private(set) var items: [ExtractedTextItem] = []
    @Published private(set) var groupedItems: [CategoryGroup] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var showingError = false

    private let imageRepository: ImageRepositoryProtocol

    init(imageRepository: ImageRepositoryProtocol) {
        self.imageRepository = imageRepository
    }

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let photos = try await imageRepository.fetchAll(sortedBy: .importedAtDescending)
            // Filter photos that have extracted text or book info
            items = photos.compactMap { photo -> ExtractedTextItem? in
                let hasContent = (photo.extractedText != nil && !photo.extractedText!.isEmpty) || photo.hasBookInfo
                guard hasContent else { return nil }

                return ExtractedTextItem(
                    id: photo.id,
                    thumbnailPath: photo.thumbnailPath,
                    extractedText: photo.extractedText,
                    bookTitle: photo.bookInfo?.title,
                    bookAuthor: photo.bookInfo?.author,
                    bookPublisher: photo.bookInfo?.publisher,
                    bookISBN: photo.bookInfo?.isbn,
                    bookCategory: photo.bookInfo?.category,
                    ocrProcessedAt: photo.ocrProcessedAt
                )
            }

            // Group items by category
            groupedItems = groupByCategory(items)
        } catch {
            self.error = error
            showingError = true
        }
    }

    private func groupByCategory(_ items: [ExtractedTextItem]) -> [CategoryGroup] {
        var grouped: [String: [ExtractedTextItem]] = [:]
        let uncategorizedKey = "未分類"

        for item in items {
            let category = item.bookCategory ?? uncategorizedKey
            grouped[category, default: []].append(item)
        }

        // Sort categories: defined categories first (alphabetically), then uncategorized at the end
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            if key1 == uncategorizedKey { return false }
            if key2 == uncategorizedKey { return true }
            return key1 < key2
        }

        return sortedKeys.map { CategoryGroup(category: $0, items: grouped[$0]!) }
    }
}

struct CategoryGroup: Identifiable {
    let id = UUID()
    let category: String
    let items: [ExtractedTextItem]
}

struct ExtractedTextItem: Identifiable {
    let id: UUID
    let thumbnailPath: String?
    let extractedText: String?
    let bookTitle: String?
    let bookAuthor: String?
    let bookPublisher: String?
    let bookISBN: String?
    let bookCategory: String?
    let ocrProcessedAt: Date?

    var hasBookInfo: Bool {
        bookTitle != nil || bookAuthor != nil || bookPublisher != nil
    }

    var displayTitle: String {
        if let title = bookTitle {
            return title
        } else if let text = extractedText {
            // Return first line or first 50 characters
            let firstLine = text.components(separatedBy: .newlines).first ?? text
            if firstLine.count > 50 {
                return String(firstLine.prefix(50)) + "..."
            }
            return firstLine
        }
        return "（テキストなし）"
    }
}
