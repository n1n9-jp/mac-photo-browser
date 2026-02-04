//
//  BookInfoService.swift
//  iOSPhotoBrowser
//

import Foundation

actor BookInfoService {
    static let shared = BookInfoService()

    private let openBDBaseURL = "https://api.openbd.jp/v1/get"
    private let ndlBaseURL = "https://ndlsearch.ndl.go.jp/api/opensearch"

    private init() {}

    // MARK: - ISBN検索 (openBD)

    func fetchBookInfo(isbn: String) async throws -> BookInfo? {
        guard let url = URL(string: "\(openBDBaseURL)?isbn=\(isbn)") else {
            throw BookInfoServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BookInfoServiceError.requestFailed
        }

        let decoder = JSONDecoder()
        let results = try decoder.decode([OpenBDResponse?].self, from: data)

        guard let firstResult = results.first, let result = firstResult else {
            return nil
        }

        return BookInfo(
            isbn: result.summary.isbn,
            title: result.summary.title,
            author: result.summary.author,
            publisher: result.summary.publisher,
            publishedDate: result.summary.pubdate,
            coverUrl: result.summary.cover
        )
    }

    // MARK: - タイトル検索 (国立国会図書館サーチ)

    func searchByTitle(keyword: String) async throws -> [BookInfo] {
        // Use 'any' parameter for full-text search (more effective than 'title')
        // Remove mediatype filter to get broader results
        guard let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(ndlBaseURL)?cnt=20&any=\(encodedKeyword)") else {
            throw BookInfoServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BookInfoServiceError.requestFailed
        }

        return parseNDLResponse(data: data)
    }

    private func parseNDLResponse(data: Data) -> [BookInfo] {
        var results: [BookInfo] = []

        guard let xmlString = String(data: data, encoding: .utf8) else {
            return results
        }

        // Simple XML parsing for NDL OpenSearch response
        let items = xmlString.components(separatedBy: "<item>")

        for (index, item) in items.enumerated() {
            guard index > 0 else { continue } // Skip the first part (before first <item>)

            let title = extractXMLValue(from: item, tag: "title")
            let author = extractXMLValue(from: item, tag: "author") ?? extractFirstXMLValue(from: item, tag: "dc:creator")
            let publisher = extractXMLValue(from: item, tag: "dc:publisher")
            // ISBN is in format: <dc:identifier xsi:type="dcndl:ISBN">978-4-xxx</dc:identifier>
            let isbn = extractISBNFromXML(from: item)
            let pubDate = extractXMLValue(from: item, tag: "dcterms:issued") ?? extractXMLValue(from: item, tag: "dc:date")
            // Category (e.g., 図書, 記事, 映像資料)
            let category = extractXMLValue(from: item, tag: "category")

            if let title = title {
                let bookInfo = BookInfo(
                    isbn: isbn ?? "",
                    title: title,
                    author: author,
                    publisher: publisher,
                    publishedDate: pubDate,
                    category: category
                )
                results.append(bookInfo)
            }
        }

        // Sort: prefer items with ISBN (books) first
        return results.sorted { ($0.isbn.isEmpty ? 1 : 0) < ($1.isbn.isEmpty ? 1 : 0) }
    }

    private func extractISBNFromXML(from xml: String) -> String? {
        // Look for ISBN in dc:identifier with xsi:type="dcndl:ISBN"
        let pattern = "<dc:identifier[^>]*xsi:type=\"dcndl:ISBN\"[^>]*>([^<]+)</dc:identifier>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        let value = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Clean ISBN (remove hyphens)
        let cleanISBN = value.filter { $0.isNumber || $0 == "X" }
        return cleanISBN.isEmpty ? nil : cleanISBN
    }

    private func extractFirstXMLValue(from xml: String, tag: String) -> String? {
        // Extract only the first occurrence (useful for dc:creator which may have multiple)
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        let value = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : decodeHTMLEntities(value)
    }

    private func extractXMLValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        let value = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : decodeHTMLEntities(value)
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'"
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }
}

// MARK: - OpenBD API Response Models

private struct OpenBDResponse: Decodable {
    let summary: OpenBDSummary
}

private struct OpenBDSummary: Decodable {
    let isbn: String
    let title: String?
    let author: String?
    let publisher: String?
    let pubdate: String?
    let cover: String?
}

enum BookInfoServiceError: Error, LocalizedError {
    case invalidURL
    case requestFailed
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URLの生成に失敗しました"
        case .requestFailed:
            return "書誌情報の取得に失敗しました"
        case .parseError:
            return "書誌情報の解析に失敗しました"
        }
    }
}

// MARK: - String Extension for ISBN extraction

private extension String {
    func extractISBN() -> String? {
        // Extract ISBN-13 or ISBN-10 from string
        let patterns = [
            "97[89][-\\s]?\\d[-\\s]?\\d{2,5}[-\\s]?\\d{2,7}[-\\s]?\\d",
            "97[89]\\d{10}",
            "\\d{9}[\\dX]"
        ]

        for pattern in patterns {
            if let range = self.range(of: pattern, options: .regularExpression) {
                let matched = String(self[range])
                let cleanISBN = matched.filter { $0.isNumber || $0 == "X" }
                if cleanISBN.count == 13 || cleanISBN.count == 10 {
                    return cleanISBN
                }
            }
        }
        return nil
    }
}
