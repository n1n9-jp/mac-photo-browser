//
//  OCRService.swift
//  MacPhotoBrowser
//

import Foundation
import Vision
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

actor OCRService {
    static let shared = OCRService()

    private init() {}

    func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: recognizedText)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Apple Intelligence OCR補正

    @available(iOS 26.0, *)
    private func correctOCRTextWithAI(_ rawText: String) async -> String {
        #if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()

            let prompt = """
            以下はOCRで読み取ったテキストです。
            OCRの誤認識を修正し、読みやすく整形してください。

            特に注意する点：
            - 数字の誤り（0とO、1とI/lなど）を修正
            - 誤字を修正
            - 不自然な改行や空白を整理

            入力テキスト:
            \(rawText)

            修正後のテキストのみを出力してください（説明不要）:
            """

            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("Apple Intelligence correction failed: \(error)")
            return rawText
        }
        #else
        return rawText
        #endif
    }

    /// OCR実行後に自動でApple Intelligence補正を適用
    func recognizeTextWithCorrection(from image: UIImage) async throws -> String {
        let rawText = try await recognizeText(from: image)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await correctOCRTextWithAI(rawText)
        }
        #endif

        return rawText
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "画像の読み込みに失敗しました"
        case .recognitionFailed:
            return "テキストの認識に失敗しました"
        }
    }
}
