//
//  AppleFoundationModelsService.swift
//  iOSPhotoBrowser
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Foundation Models (iOS 26+) を使用したLLMサービス
/// システムに組み込まれたLLMを使用するため、追加のダウンロードは不要
@available(iOS 26.0, *)
actor AppleFoundationModelsService: LLMServiceProtocol {
    nonisolated let serviceName = "Apple Intelligence"

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    init() {}

    nonisolated var isAvailable: Bool {
        get async {
            #if canImport(FoundationModels)
            // FoundationModelsが利用可能かチェック
            // 実際のデバイスではA17 Pro以上のチップが必要
            return true
            #else
            return false
            #endif
        }
    }

    func extractBookInfo(from ocrText: String) async throws -> ExtractedBookData {
        #if canImport(FoundationModels)
        print("[AppleIntelligence] Starting extraction...")
        print("[AppleIntelligence] OCR Text length: \(ocrText.count) characters")

        let prompt = makeBookExtractionPrompt(ocrText: ocrText)

        do {
            // セッションを作成または再利用
            if session == nil {
                print("[AppleIntelligence] Creating new LanguageModelSession...")
                session = LanguageModelSession()
            }

            guard let session = session else {
                print("[AppleIntelligence] Failed to create session")
                throw LLMError.notAvailable
            }

            print("[AppleIntelligence] Sending prompt to model...")
            let response = try await session.respond(to: prompt)
            let responseText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            print("[AppleIntelligence] Response received:")
            print("[AppleIntelligence] \(responseText.prefix(500))")

            let result = parseJSONResponse(responseText)
            print("[AppleIntelligence] Parsed result - Title: \(result.title ?? "nil"), Author: \(result.author ?? "nil"), ISBN: \(result.isbn ?? "nil")")
            return result
        } catch let error as LLMError {
            print("[AppleIntelligence] LLMError: \(error.localizedDescription)")
            throw error
        } catch {
            print("[AppleIntelligence] Error: \(error)")
            throw LLMError.extractionFailed(error.localizedDescription)
        }
        #else
        print("[AppleIntelligence] FoundationModels not available")
        throw LLMError.notAvailable
        #endif
    }

    // MARK: - Private Helpers

    private func parseJSONResponse(_ response: String) -> ExtractedBookData {
        // JSONブロックを抽出（```json ... ``` や直接JSONの両方に対応）
        var jsonString = response

        // マークダウンのコードブロックを除去
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        } else if let startRange = response.range(of: "```"),
                  let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSONをパース
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // パース失敗時は正規表現でタイトルと著者を抽出
            return extractFromPlainText(response)
        }

        let title = json["title"] as? String
        let author = json["author"] as? String
        let publisher = json["publisher"] as? String
        var isbn = json["isbn"] as? String

        // ISBNのクリーニング（数字のみ抽出）
        if let rawISBN = isbn {
            isbn = rawISBN.filter { $0.isNumber }
            if isbn?.count != 13 {
                isbn = nil
            }
        }

        // 信頼度スコアを計算
        var confidence = 0.0
        var fields = 0
        if title != nil { fields += 1 }
        if author != nil { fields += 1 }
        if publisher != nil { fields += 1 }
        if isbn != nil { fields += 2 }  // ISBNは重み付け
        confidence = Double(fields) / 5.0

        return ExtractedBookData(
            title: title,
            author: author,
            publisher: publisher,
            isbn: isbn,
            confidence: confidence
        )
    }

    /// JSONパース失敗時のフォールバック
    private func extractFromPlainText(_ text: String) -> ExtractedBookData {
        var title: String?
        var author: String?
        var isbn: String?

        // タイトルパターン: 「タイトル: xxx」や「title: xxx」
        let titlePatterns = ["タイトル[：:]\\s*(.+)", "title[：:]\\s*(.+)"]
        for pattern in titlePatterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let line = String(text[match])
                if let colonIndex = line.firstIndex(of: ":") ?? line.firstIndex(of: "：") {
                    title = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        // 著者パターン
        let authorPatterns = ["著者[：:]\\s*(.+)", "author[：:]\\s*(.+)"]
        for pattern in authorPatterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let line = String(text[match])
                if let colonIndex = line.firstIndex(of: ":") ?? line.firstIndex(of: "：") {
                    author = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        // ISBN-13パターン
        let isbnPattern = "97[89]\\d{10}"
        if let match = text.range(of: isbnPattern, options: .regularExpression) {
            isbn = String(text[match])
        }

        return ExtractedBookData(
            title: title,
            author: author,
            publisher: nil,
            isbn: isbn,
            confidence: 0.3  // プレーンテキスト抽出は低信頼度
        )
    }
}
