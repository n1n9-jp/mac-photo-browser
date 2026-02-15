//
//  AutoTaggingService.swift
//  MacPhotoBrowser
//
//  写真のインポート時に自動でタグと説明文を抽出するサービス
//

import Foundation
import UIKit

actor AutoTaggingService {
    private let tagRepository: TagRepositoryProtocol
    private let imageRepository: ImageRepositoryProtocol

    init(tagRepository: TagRepositoryProtocol, imageRepository: ImageRepositoryProtocol) {
        self.tagRepository = tagRepository
        self.imageRepository = imageRepository
    }

    /// 画像に対して自動タグ付けと説明文生成を実行
    /// Cloud API → VLM → OCR+LLM のフォールバックチェーンで処理
    func processImage(imageId: UUID, image: UIImage) async {
        print("[AutoTagging] Starting for image: \(imageId)")

        // LLMで最適な方法でタグを抽出
        var ocrText: String?

        // OCRテキストを事前に取得（LLMフォールバック用）
        do {
            ocrText = try await OCRService.shared.recognizeText(from: image)
            if let text = ocrText, !text.isEmpty {
                // OCRテキストも保存
                try await imageRepository.updateExtractedText(
                    imageId: imageId,
                    text: text,
                    processedAt: Date()
                )
                print("[AutoTagging] OCR text saved: \(text.prefix(100))...")
            }
        } catch {
            print("[AutoTagging] OCR failed: \(error.localizedDescription)")
        }

        // タグ抽出（最適な方法を自動選択）
        let tagData = await LLMService.shared.extractTagsBestMethod(
            image: image,
            ocrText: ocrText
        )

        guard tagData.hasValidData else {
            print("[AutoTagging] No valid tags extracted")
            return
        }

        print("[AutoTagging] Extracted \(tagData.tags.count) tags, description: \(tagData.description?.prefix(50) ?? "nil")")

        // タグを保存
        for tagName in tagData.tags {
            let normalizedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedName.isEmpty else { continue }

            let tag = Tag(name: normalizedName)
            do {
                try await tagRepository.addTag(tag, to: imageId)
                print("[AutoTagging] Tag added: \(normalizedName)")
            } catch {
                print("[AutoTagging] Failed to add tag '\(normalizedName)': \(error.localizedDescription)")
            }
        }

        // 説明文を保存
        if let description = tagData.description, !description.isEmpty {
            do {
                try await imageRepository.updateAIDescription(
                    imageId: imageId,
                    description: description,
                    processedAt: Date()
                )
                print("[AutoTagging] Description saved")
            } catch {
                print("[AutoTagging] Failed to save description: \(error.localizedDescription)")
            }
        }

        print("[AutoTagging] Completed for image: \(imageId)")
    }
}
