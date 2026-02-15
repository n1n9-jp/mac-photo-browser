//
//  AutoTaggingService.swift
//  MacPhotoBrowser
//
//  写真のインポート時に自動でタグと説明文を抽出するサービス
//

import Foundation
import UIKit
import CoreLocation

actor AutoTaggingService {
    private let tagRepository: TagRepositoryProtocol
    private let imageRepository: ImageRepositoryProtocol

    init(tagRepository: TagRepositoryProtocol, imageRepository: ImageRepositoryProtocol) {
        self.tagRepository = tagRepository
        self.imageRepository = imageRepository
    }

    /// 画像に対して自動タグ付けと説明文生成を実行
    /// 1. EXIF情報から即座にタグ付け（カメラ・季節・時間帯・場所）
    /// 2. Cloud API → VLM → OCR+LLM のフォールバックチェーンでAIタグ付け
    func processImage(imageId: UUID, image: UIImage, metadata: ImageMetadata? = nil) async {
        print("[AutoTagging] Starting for image: \(imageId)")

        // EXIF情報からタグを即座に抽出・保存
        if let metadata = metadata {
            let exifTags = await extractTagsFromMetadata(metadata)
            for tagName in exifTags {
                await addTag(tagName, to: imageId)
            }
            if !exifTags.isEmpty {
                print("[AutoTagging] EXIF tags added: \(exifTags.joined(separator: ", "))")
            }
        }

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
            await addTag(tagName, to: imageId)
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

    // MARK: - EXIF Metadata Tag Extraction

    /// EXIF情報からタグを生成
    private func extractTagsFromMetadata(_ metadata: ImageMetadata) async -> [String] {
        var tags: [String] = []

        // カメラ機種からタグ生成
        if let cameraTag = cameraTag(from: metadata) {
            tags.append(cameraTag)
        }

        // 撮影日時から季節・時間帯タグ
        if let date = metadata.capturedAt {
            tags.append(seasonTag(from: date))
            if let timeTag = timeOfDayTag(from: date) {
                tags.append(timeTag)
            }
        }

        // GPS座標から地名タグ
        if let lat = metadata.latitude, let lon = metadata.longitude {
            if let locationTag = await reverseGeocode(latitude: lat, longitude: lon) {
                tags.append(locationTag)
            }
        }

        return tags
    }

    /// カメラ機種名からタグを生成
    private func cameraTag(from metadata: ImageMetadata) -> String? {
        if let model = metadata.cameraModel {
            // "iPhone 15 Pro Max" → "iphone", "Canon EOS R5" → "canon" etc.
            let normalized = model.lowercased()
            if normalized.contains("iphone") {
                return "iphone"
            } else if normalized.contains("ipad") {
                return "ipad"
            } else if let make = metadata.cameraMake?.lowercased() {
                // カメラメーカー名をタグに（canon, nikon, sony, fujifilm 等）
                let knownMakes = ["canon", "nikon", "sony", "fujifilm", "olympus", "panasonic", "leica", "ricoh", "pentax", "hasselblad", "gopro", "dji"]
                for known in knownMakes {
                    if make.contains(known) {
                        return known
                    }
                }
                return make.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }
        return nil
    }

    /// 撮影日から季節タグを生成
    private func seasonTag(from date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3, 4, 5: return "春"
        case 6, 7, 8: return "夏"
        case 9, 10, 11: return "秋"
        default: return "冬"
        }
    }

    /// 撮影時刻から時間帯タグを生成
    private func timeOfDayTag(from date: Date) -> String? {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<7: return "早朝"
        case 7..<10: return "朝"
        case 16..<18: return "夕方"
        case 18..<21: return "夜"
        case 21..<24, 0..<5: return "深夜"
        default: return nil  // 昼間(10-16時)は特徴的でないのでタグ化しない
        }
    }

    /// GPS座標から逆ジオコーディングで地名を取得
    private func reverseGeocode(latitude: Double, longitude: Double) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            // 市区町村名を優先、なければ都道府県名
            if let locality = placemark.locality {
                return locality
            } else if let state = placemark.administrativeArea {
                return state
            }
            return nil
        } catch {
            print("[AutoTagging] Reverse geocoding failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helper

    /// タグ名を正規化して保存
    private func addTag(_ tagName: String, to imageId: UUID) async {
        let normalizedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else { return }

        let tag = Tag(name: normalizedName)
        do {
            try await tagRepository.addTag(tag, to: imageId)
            print("[AutoTagging] Tag added: \(normalizedName)")
        } catch {
            print("[AutoTagging] Failed to add tag '\(normalizedName)': \(error.localizedDescription)")
        }
    }
}
