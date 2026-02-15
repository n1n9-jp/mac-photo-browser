//
//  AppleFoundationModelsService.swift
//  MacPhotoBrowser
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
            return true
            #else
            return false
            #endif
        }
    }

    func extractTags(from ocrText: String) async throws -> ExtractedTagData {
        #if canImport(FoundationModels)
        print("[AppleIntelligence] Starting tag extraction...")
        print("[AppleIntelligence] OCR Text length: \(ocrText.count) characters")

        // システムプロンプトのルールをユーザープロンプトに結合
        // （Apple Intelligence はシステムロールを直接サポートしないため）
        let prompt = """
        \(TaggingPrompts.system)

        \(TaggingPrompts.userPromptForOCR(ocrText))
        """

        do {
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

            let result = TaggingPrompts.parseJSONResponse(responseText)
            if result.hasValidData {
                print("[AppleIntelligence] Parsed result - Tags: \(result.tags), Description: \(result.description ?? "nil")")
                return result
            }
            let fallback = extractTagsFromPlainText(responseText)
            print("[AppleIntelligence] Fallback result - Tags: \(fallback.tags)")
            return fallback
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

    /// JSONパース失敗時のフォールバック
    private func extractTagsFromPlainText(_ text: String) -> ExtractedTagData {
        // カンマやスペースで区切られたキーワードを抽出
        var tags: [String] = []

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "- tag" や "* tag" 形式のリスト
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•") {
                let tag = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !tag.isEmpty && tag.count < 30 {
                    tags.append(tag)
                }
            }
        }

        // リスト形式でなければカンマ区切りを試行
        if tags.isEmpty {
            let candidates = text.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count < 30 }
            tags = candidates
        }

        return ExtractedTagData(
            tags: tags,
            description: nil,
            confidence: 0.3
        )
    }
}
