//
//  AutoTaggingService.swift
//  MacPhotoBrowser
//
//  写真のインポート時に自動でタグと説明文を抽出するサービス
//

import Foundation
import UIKit
import CoreLocation
import NaturalLanguage

actor AutoTaggingService {
    private let tagRepository: TagRepositoryProtocol
    private let imageRepository: ImageRepositoryProtocol

    init(tagRepository: TagRepositoryProtocol, imageRepository: ImageRepositoryProtocol) {
        self.tagRepository = tagRepository
        self.imageRepository = imageRepository
    }

    /// 画像に対して自動タグ付けと説明文生成を実行
    /// 1. EXIF情報から即座にタグ付け（カメラ・季節・時間帯・場所）
    /// 2. 画像ベースAI（Cloud API → VLM）を優先試行
    /// 3. 画像ベースが失敗した場合のみ OCR → 品質チェック → LLMでタグ付け
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

        // --- 画像ベースAI抽出を最優先で試行 ---
        var tagData = ExtractedTagData()
        var imageBasedSuccess = false

        // Cloud APIで画像から直接抽出（最高精度）
        if await LLMService.shared.isCloudAPIAvailable() {
            do {
                let result = try await LLMService.shared.extractTagsFromImageWithCloud(image)
                if result.hasValidData {
                    tagData = result
                    imageBasedSuccess = true
                    print("[AutoTagging] Image-based extraction succeeded (Cloud API)")
                }
            } catch {
                print("[AutoTagging] Cloud API image extraction failed: \(error.localizedDescription)")
            }
        }

        // VLMで画像から直接抽出
        if !imageBasedSuccess, await LLMService.shared.isVLMAvailable() {
            let result = await LLMService.shared.extractTagsFromImageOrEmpty(image)
            if result.hasValidData {
                tagData = result
                imageBasedSuccess = true
                print("[AutoTagging] Image-based extraction succeeded (VLM)")
            }
        }

        // --- OCRテキスト抽出（常に実行して保存用、Apple Intelligence補正付き） ---
        var ocrText: String?
        do {
            ocrText = try await OCRService.shared.recognizeTextWithCorrection(from: image)
            if let text = ocrText, !text.isEmpty {
                try await imageRepository.updateExtractedText(
                    imageId: imageId,
                    text: text,
                    processedAt: Date()
                )
                print("[AutoTagging] OCR text saved: \(text.prefix(100))...")

                // ハッシュタグを検出して即座にタグ化（SNS投稿画像等）
                let hashtags = extractHashtags(from: text)
                for tag in hashtags {
                    guard validateTag(tag) else { continue }
                    await addTag(tag, to: imageId)
                }
                if !hashtags.isEmpty {
                    print("[AutoTagging] Hashtags extracted: \(hashtags.joined(separator: ", "))")
                }

                // OCRテキストからキーワード（名詞・固有名詞）を直接抽出してタグ化
                // LLMに頼らず、自然言語処理で確実にタグを生成
                let keywords = extractKeywordsFromOCR(text)
                for keyword in keywords {
                    guard validateTag(keyword) else { continue }
                    await addTag(keyword, to: imageId)
                }
                if !keywords.isEmpty {
                    print("[AutoTagging] OCR keywords extracted: \(keywords.joined(separator: ", "))")
                }
            }
        } catch {
            print("[AutoTagging] OCR failed: \(error.localizedDescription)")
        }

        // --- 画像ベースが失敗した場合のみ、OCRテキストからLLMでタグ付け ---
        if !imageBasedSuccess {
            if let text = ocrText, isOCRTextUsable(text) {
                print("[AutoTagging] Falling back to OCR+LLM (text length: \(text.count))")
                let result = await LLMService.shared.extractTagsOrEmpty(from: text)
                if result.hasValidData {
                    tagData = result
                    print("[AutoTagging] OCR+LLM extraction succeeded")
                }
            } else {
                print("[AutoTagging] OCR text not usable for LLM tagging, skipping")
            }
        }

        guard tagData.hasValidData else {
            print("[AutoTagging] No valid tags extracted")
            return
        }

        print("[AutoTagging] Extracted \(tagData.tags.count) tags, description: \(tagData.description?.prefix(50) ?? "nil")")

        // タグを保存（バリデーション付き）
        for tagName in tagData.tags {
            guard validateTag(tagName) else {
                print("[AutoTagging] Tag rejected by validation: '\(tagName)'")
                continue
            }
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

    // MARK: - Hashtag Extraction

    /// OCRテキストからハッシュタグ（#タグ）を抽出してタグ名のリストを返す
    /// 例: "#風景 #Tokyo #写真好きな人と繋がりたい" → ["風景", "tokyo"]
    private func extractHashtags(from text: String) -> [String] {
        // #（半角）と＃（全角）の両方に対応
        // ハッシュタグの後に続く文字列（スペース・改行まで）を抽出
        let pattern = "[#＃]([\\p{L}\\p{N}_]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var tags: [String] = []
        var seen = Set<String>()

        for match in matches {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let tag = String(text[range])
            let normalized = tag.lowercased()

            // 重複除外、バリデーション通過のもののみ
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            tags.append(tag)
        }

        return tags
    }

    // MARK: - OCR Keyword Extraction

    /// OCRテキストから名詞・固有名詞をNLTaggerで抽出し、タグ候補として返す
    /// LLM不要で確実にキーワードを取得できる
    private func extractKeywordsFromOCR(_ text: String) -> [String] {
        var keywords: [String] = []
        var seen = Set<String>()

        // NLTaggerで品詞タグ付け（日本語・英語対応）
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, range in
            guard let tag = tag else { return true }

            // 名詞・固有名詞・その他の名詞的要素を抽出
            let isRelevant = tag == .noun || tag == .placeName || tag == .personalName || tag == .organizationName
            guard isRelevant else { return true }

            let word = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)

            // 2文字以上のキーワードのみ
            guard word.count >= 2 else { return true }

            let normalized = word.lowercased()
            guard !seen.contains(normalized) else { return true }
            seen.insert(normalized)

            keywords.append(word)
            return true
        }

        // 上位5個に絞る（多すぎるタグを防止）
        return Array(keywords.prefix(5))
    }

    // MARK: - OCR Quality Gate

    /// OCRテキストがLLMタグ付けに十分な品質かチェック
    private func isOCRTextUsable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 最低10文字以上（短すぎると推測が不安定）
        guard trimmed.count >= 10 else { return false }
        // 意味のある文字が30%以上含まれているか（記号やゴミだけではないか）
        let letterCount = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return Double(letterCount) / Double(trimmed.count) > 0.3
    }

    // MARK: - Tag Validation

    /// タグ名の妥当性を検証（ゴミタグ・無意味なタグを除外）
    private func validateTag(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 2文字未満は除外
        guard trimmed.count >= 2 else { return false }
        // 20文字超は除外（タグとして長すぎる）
        guard trimmed.count <= 20 else { return false }
        // 文字（ひらがな・カタカナ・漢字・英字）を含むこと（数字・記号のみは不可）
        let hasLetters = trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        guard hasLetters else { return false }
        // 既知のゴミパターンを除外
        let junkPatterns = ["タグ", "タグ1", "タグ2", "タグ3", "tag", "tag1", "tag2", "tag3",
                            "不明", "unknown", "その他", "none", "null", "n/a", "写真", "画像",
                            "image", "photo", "picture"]
        guard !junkPatterns.contains(trimmed.lowercased()) else { return false }
        return true
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

    // MARK: - Synonym Normalization

    /// 同義語・表記揺れの正規化テーブル
    /// key: 正規化前（lowercased）, value: 正規化後
    private static let synonymMap: [String: String] = [
        // 英語→日本語（よく出現する基本語彙）
        "cat": "猫", "cats": "猫",
        "dog": "犬", "dogs": "犬",
        "flower": "花", "flowers": "花",
        "tree": "木", "trees": "木",
        "mountain": "山", "mountains": "山",
        "ocean": "海", "sea": "海",
        "river": "川",
        "sky": "空",
        "sun": "太陽", "sunset": "夕焼け", "sunrise": "朝焼け",
        "moon": "月",
        "snow": "雪",
        "rain": "雨",
        "food": "料理", "meal": "料理",
        "building": "建物", "buildings": "建物",
        "car": "車", "cars": "車",
        "train": "電車",
        "bridge": "橋",
        "temple": "寺", "shrine": "神社",
        "park": "公園",
        "beach": "海岸",
        "forest": "森",
        "night": "夜景",
        "city": "街並み", "cityscape": "街並み",
        "person": "人物", "people": "人物",
        "child": "子供", "children": "子供",
        "baby": "赤ちゃん",
        "bird": "鳥", "birds": "鳥",
        "fish": "魚",
        "restaurant": "レストラン",
        "cafe": "カフェ", "coffee": "コーヒー",
        // カタカナ→漢字・統一表記
        "ネコ": "猫", "ねこ": "猫",
        "イヌ": "犬", "いぬ": "犬",
        "ヤマ": "山", "やま": "山",
        "ウミ": "海", "うみ": "海",
        "ソラ": "空", "そら": "空",
        "ハナ": "花", "はな": "花",
        // 類義語統一
        "海辺": "海岸", "浜辺": "海岸", "ビーチ": "海岸",
        "夕暮れ": "夕焼け", "夕日": "夕焼け",
        "朝日": "朝焼け",
        "お寺": "寺", "寺院": "寺",
        "お店": "店舗", "ショップ": "店舗",
    ]

    /// タグ名を同義語テーブルで正規化
    private func normalizeSynonym(_ name: String) -> String {
        let lowered = name.lowercased()
        return Self.synonymMap[lowered] ?? name
    }

    // MARK: - Helper

    /// タグ名を正規化して保存（同義語正規化 + lowercased + trim）
    private func addTag(_ tagName: String, to imageId: UUID) async {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let synonymNormalized = normalizeSynonym(trimmed)
        let normalizedName = synonymNormalized.lowercased()
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
