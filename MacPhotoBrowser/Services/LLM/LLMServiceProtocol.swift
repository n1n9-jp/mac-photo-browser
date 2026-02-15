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
///
/// 設計原則:
/// - 構造化タクソノミー: カテゴリ別にタグを要求（objects/scene/attributes/mood）
/// - Chain-of-Thought: まず画像を観察し分析してからタグ生成（ハルシネーション抑制）
/// - Few-shot: 具体的な入出力例を提示してフォーマットと品質を安定化
enum TaggingPrompts {

    /// システムプロンプト（Claude API等、system roleをサポートするモデル向け）
    static let system = """
    あなたは写真の内容を正確に分析し、構造化されたタグと説明文を生成する画像分析エキスパートです。

    ## ルール
    1. **実際に写っているものだけ**をタグにする。推測・連想は禁止。
    2. 日本語でタグと説明を生成する。
    3. 各カテゴリのタグは必要な分だけ（0〜3個）。合計3〜7個に厳選。
    4. 意味が重なるタグは1つにまとめる（例: "猫"と"ネコ"は片方だけ）。
    5. 抽象的すぎるタグ（"写真", "画像", "風景"のみ等）は禁止。具体的に。
    6. 出力は必ず valid JSON のみ。それ以外のテキストは禁止。

    ## タグのカテゴリ（タクソノミー）
    - **objects**: 写っている具体的な被写体（人物、動物、食べ物、乗り物、建物 等）
    - **scene**: 場所やシーンの種類（レストラン、公園、オフィス、海辺、山道 等）
    - **attributes**: 色、状態、特徴（赤い、雪景色、手書き、ネオン 等）
    - **mood**: 雰囲気（にぎやか、静か、レトロ、モダン 等）

    ## 出力形式
    {"analysis": "画像の観察結果", "tags": {"objects": [...], "scene": [...], "attributes": [...], "mood": [...]}, "description": "1-2文の説明"}
    """

    /// OCRテキストからの抽出用ユーザープロンプト
    static func userPromptForOCR(_ ocrText: String) -> String {
        """
        写真から読み取られたテキストを元に、写真の内容を分析してタグと説明文を生成してください。

        **重要**: テキストに書かれている情報のみに基づいてタグを生成してください。テキストに含まれない内容を推測・連想しないでください。

        ## 手順（Chain-of-Thought）
        1. まず、テキストの内容を読み取り、何についてのテキストか分析する（analysisに記述）
        2. 分析結果に基づいて、カテゴリ別にタグを生成する
        3. 説明文を1-2文で生成する

        ## テキスト:
        \(ocrText)

        ## 出力例1:
        {"analysis": "居酒屋のメニュー表。刺身盛り合わせや焼き鳥などの料理名と価格が記載されている", "tags": {"objects": ["メニュー", "居酒屋"], "scene": ["飲食店"], "attributes": ["和食"], "mood": []}, "description": "居酒屋のメニュー表。刺身や焼き鳥などの料理が並ぶ"}

        ## 出力例2:
        {"analysis": "イベントのポスター。2024年花火大会の開催日時と場所が記載されている", "tags": {"objects": ["ポスター", "花火大会"], "scene": [], "attributes": [], "mood": []}, "description": "花火大会の告知ポスター"}

        ## 出力（JSONのみ、他のテキスト禁止）:
        """
    }

    /// 画像からの直接抽出用ユーザープロンプト
    static let userPromptForImage = """
    この写真を分析し、構造化されたタグと説明文を生成してください。

    ## 手順（Chain-of-Thought）
    1. まず、写真に何が写っているか注意深く観察する（analysisに記述）
    2. 観察結果に基づいて、カテゴリ別にタグを生成する（**写っているものだけ**）
    3. 説明文を1-2文で生成する

    ## カテゴリ
    - objects: 具体的な被写体（人物、動物、食べ物、建物 等）
    - scene: 場所やシーン（レストラン、公園、街中 等）
    - attributes: 色、状態、特徴（赤い、手書き、ネオン 等）
    - mood: 雰囲気（にぎやか、静か、レトロ 等）

    ## 出力例1:
    {"analysis": "テーブルの上にラーメンの丼が置かれている。背景に店内のカウンターが見える", "tags": {"objects": ["ラーメン", "丼"], "scene": ["ラーメン店"], "attributes": [], "mood": []}, "description": "ラーメン店のカウンターに置かれたラーメン"}

    ## 出力例2:
    {"analysis": "夕暮れ時の海岸。波打ち際に人のシルエットが見える。空がオレンジ色に染まっている", "tags": {"objects": ["人物"], "scene": ["海岸"], "attributes": ["夕焼け", "シルエット"], "mood": ["静か"]}, "description": "夕焼けに染まる海岸と人のシルエット"}

    ## 出力（JSONのみ、他のテキスト禁止）:
    """

    /// JSON応答をパースしてExtractedTagDataに変換する共通処理
    /// v2（構造化タクソノミー）とv1（フラットタグ）の両方に対応
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

        let description = json["description"] as? String
        var tags: [String] = []

        // v2: 構造化タクソノミー形式 {"tags": {"objects": [...], "scene": [...], ...}}
        if let tagsDict = json["tags"] as? [String: Any] {
            // 辞書の場合、全カテゴリのタグを結合
            for category in ["objects", "scene", "attributes", "mood"] {
                if let categoryTags = tagsDict[category] as? [String] {
                    tags.append(contentsOf: categoryTags)
                }
            }
            // 辞書だが既知カテゴリにマッチしない場合（モデルが独自カテゴリを使った場合）
            if tags.isEmpty {
                for (_, value) in tagsDict {
                    if let arr = value as? [String] {
                        tags.append(contentsOf: arr)
                    }
                }
            }
        }

        // v1: フラットタグ形式 {"tags": ["tag1", "tag2"]}
        if tags.isEmpty, let flatTags = json["tags"] as? [String] {
            tags = flatTags
        }

        let confidence = tags.isEmpty ? 0.0 : min(Double(tags.count) / 5.0, 1.0)

        return ExtractedTagData(
            tags: tags,
            description: description,
            confidence: confidence
        )
    }
}
