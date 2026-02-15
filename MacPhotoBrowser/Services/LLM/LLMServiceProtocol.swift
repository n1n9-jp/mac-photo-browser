//
//  LLMServiceProtocol.swift
//  MacPhotoBrowser
//

import Foundation

// MARK: - Extracted Data Model

/// LLMが抽出したタグと説明文
struct ExtractedTagData: Sendable {
    var tags: [String]
    var description: String?
    var confidence: Double  // 0.0-1.0 の信頼度スコア

    init(
        tags: [String] = [],
        description: String? = nil,
        confidence: Double = 0.0
    ) {
        self.tags = tags
        self.description = description
        self.confidence = confidence
    }

    /// 有効なデータが含まれているかどうか
    var hasValidData: Bool {
        !tags.isEmpty || description != nil
    }
}

// MARK: - LLM Service Protocol

/// LLMサービスのプロトコル
/// 各LLM実装（Apple Foundation Models、llama.cpp）はこのプロトコルに準拠する
protocol LLMServiceProtocol {
    /// OCRテキストからタグと説明文を抽出
    func extractTags(from ocrText: String) async throws -> ExtractedTagData

    /// サービスが利用可能かどうか
    var isAvailable: Bool { get async }

    /// サービス名（デバッグ・表示用）
    var serviceName: String { get }
}

// MARK: - VLM Service Protocol

import UIKit

/// Vision Language Model サービスのプロトコル
/// 画像から直接タグと説明文を抽出（OCR不要）
protocol VLMServiceProtocol {
    /// 画像からタグと説明文を抽出
    func extractTags(from image: UIImage) async throws -> ExtractedTagData

    /// サービスが利用可能かどうか
    var isAvailable: Bool { get async }

    /// サービス名（デバッグ・表示用）
    var serviceName: String { get }

    /// モデルをメモリに読み込む
    func loadModel() async throws

    /// モデルをメモリから解放
    func unloadModel() async
}

// MARK: - LLM Errors

enum LLMError: Error, LocalizedError {
    case notAvailable
    case modelNotLoaded
    case extractionFailed(String)
    case invalidResponse
    case downloadFailed(String)
    case insufficientStorage

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "LLMサービスが利用できません"
        case .modelNotLoaded:
            return "モデルが読み込まれていません"
        case .extractionFailed(let reason):
            return "タグ抽出に失敗しました: \(reason)"
        case .invalidResponse:
            return "無効なレスポンスです"
        case .downloadFailed(let reason):
            return "モデルのダウンロードに失敗しました: \(reason)"
        case .insufficientStorage:
            return "ストレージ容量が不足しています"
        }
    }
}

// MARK: - LLM Configuration

/// LLMサービスの設定
enum LLMEnginePreference: String, CaseIterable {
    case auto = "auto"
    case cloudAPI = "cloud"
    case appleIntelligence = "apple"
    case localModel = "local"
    case none = "none"

    var displayName: String {
        switch self {
        case .auto: return "自動（推奨）"
        case .cloudAPI: return "クラウドAPI"
        case .appleIntelligence: return "Apple Intelligence"
        case .localModel: return "ローカルモデル"
        case .none: return "使用しない"
        }
    }

    var description: String {
        switch self {
        case .auto: return "クラウドAPI → Apple Intelligence → ローカルの順で自動選択"
        case .cloudAPI: return "Claude APIで高精度なタグ付け（要APIキー・通信）"
        case .appleIntelligence: return "iOS 26以降で利用可能"
        case .localModel: return "オフライン対応、約2GBのダウンロードが必要"
        case .none: return "LLMを使用しない"
        }
    }
}

// MARK: - Unified Prompt Templates

/// 全LLMサービス共通のプロンプト定義
/// モデルを跨いでも同一スキーマ・同一出力制約で統一する
enum TaggingPrompts {

    /// システムプロンプト（Claude API等、system roleをサポートするモデル向け）
    static let system = """
    あなたは写真の内容を分析し、適切なタグと簡潔な説明文を生成するAIアシスタントです。

    以下のルールを厳守してください：
    1. 写真の内容を正確に分析してください。推測は最小限に。
    2. 日本語でタグと説明を生成してください。
    3. タグは3〜10個、簡潔なキーワードで。
    4. 説明文は1〜2文で、写真の主要な内容を要約。
    5. 出力は必ず valid JSON のみ。それ以外のテキストは禁止。

    タグの例: "風景", "海", "夕焼け", "料理", "ラーメン", "街並み", "建物", "自然", "人物", "動物", "猫", "花", "山", "空", "夜景"

    出力形式:
    {"tags": ["タグ1", "タグ2", "タグ3"], "description": "写真の簡潔な説明"}
    """

    /// OCRテキストからの抽出用ユーザープロンプト
    static func userPromptForOCR(_ ocrText: String) -> String {
        """
        写真から抽出されたテキストを元に、写真の内容を推測してタグと説明文を生成してください。

        テキスト:
        \(ocrText)

        出力形式（JSONのみ、説明不要）:
        {"tags": ["タグ1", "タグ2"], "description": "内容の要約"}
        """
    }

    /// 画像からの直接抽出用ユーザープロンプト
    static let userPromptForImage = """
    この写真を分析し、適切なタグと簡潔な説明文を生成してください。

    ルール:
    - 写真に写っている被写体、場所、雰囲気、色合い等からタグを生成
    - タグは3〜10個
    - 説明文は1〜2文で写真の内容を要約
    - 日本語で出力

    出力形式（JSONのみ、説明不要）:
    {"tags": ["タグ1", "タグ2", "タグ3"], "description": "写真の簡潔な説明"}
    """

    /// JSON応答をパースしてExtractedTagDataに変換する共通処理
    static func parseJSONResponse(_ response: String) -> ExtractedTagData {
        var jsonString = response

        // マークダウンコードブロックを除去
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        } else if let startRange = response.range(of: "```"),
                  let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        }

        // 最初の { から最後の } までを抽出
        if let startIndex = jsonString.firstIndex(of: "{"),
           let endIndex = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[startIndex...endIndex])
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[TaggingPrompts] Failed to parse JSON: \(jsonString.prefix(200))")
            return ExtractedTagData()
        }

        let tags = (json["tags"] as? [String]) ?? []
        let description = json["description"] as? String

        let confidence = tags.isEmpty ? 0.0 : min(Double(tags.count) / 5.0, 1.0)

        return ExtractedTagData(
            tags: tags,
            description: description,
            confidence: confidence
        )
    }
}
