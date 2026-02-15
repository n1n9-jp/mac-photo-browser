//
//  OCRService.swift
//  MacPhotoBrowser
//

import Foundation
import Vision
import UIKit
import CoreImage

#if canImport(FoundationModels)
import FoundationModels
#endif

actor OCRService {
    static let shared = OCRService()

    /// 信頼度のしきい値（これ未満のテキストは除外）
    private let minimumConfidence: Float = 0.3

    private init() {}

    func recognizeText(from image: UIImage) async throws -> String {
        // 画像前処理でOCR精度を向上
        let processedImage = preprocessImageForOCR(image)

        guard let cgImage = processedImage.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let minConfidence = self.minimumConfidence

            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                // 信頼度フィルタリング: 低信頼度のテキストを除外
                let recognizedText = observations.compactMap { observation -> String? in
                    guard let candidate = observation.topCandidates(1).first,
                          candidate.confidence >= minConfidence else {
                        return nil
                    }
                    return candidate.string
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

    // MARK: - Image Preprocessing

    /// OCR精度向上のための画像前処理
    /// - コントラスト補正
    /// - シャープネス補正
    /// - 向きの正規化
    private func preprocessImageForOCR(_ image: UIImage) -> UIImage {
        // 向きを正規化（EXIF orientationを適用）
        let normalizedImage = normalizeOrientation(image)

        guard let ciImage = CIImage(image: normalizedImage) else {
            return normalizedImage
        }

        let context = CIContext()
        var processedImage = ciImage

        // コントラスト補正（テキストと背景の差を強調）
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(processedImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.15, forKey: kCIInputContrastKey)  // 軽いコントラスト強調
            contrastFilter.setValue(0.0, forKey: kCIInputBrightnessKey)
            if let output = contrastFilter.outputImage {
                processedImage = output
            }
        }

        // シャープネス補正（文字のエッジを強調）
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(processedImage, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.4, forKey: kCIInputSharpnessKey)
            if let output = sharpenFilter.outputImage {
                processedImage = output
            }
        }

        guard let cgImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            return normalizedImage
        }

        return UIImage(cgImage: cgImage)
    }

    /// EXIF orientationを適用して画像の向きを正規化
    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? image
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
