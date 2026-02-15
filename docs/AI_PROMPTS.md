# AI プロンプト一覧

本プロジェクトでは、写真の自動タグ付けと説明文生成を目的として、複数のAIモデルを利用しています。

## プロンプト設計方針

全モデルで **同一スキーマ・同一出力制約** の統一プロンプトを使用しています（`TaggingPrompts` enum in `LLMServiceProtocol.swift`）。

### 設計原則（v2）

1. **構造化タクソノミー** — フラットなタグリストではなく、カテゴリ別に要求（objects/scene/attributes/mood）
2. **Chain-of-Thought (CoT)** — まず画像を観察・分析し、その後タグを生成（ハルシネーション抑制）
3. **Few-shot 例** — 具体的な入出力例を提示してフォーマットと品質を安定化
4. **「写っているものだけ」ルール** — 推測・連想を明示的に禁止

### 基本ルール
1. **実際に写っているものだけをタグにする。推測・連想は禁止。**
2. **日本語でタグと説明を生成。**
3. **各カテゴリ0〜3個、合計3〜7個に厳選。意味が重なるタグは1つにまとめる。**
4. **抽象的すぎるタグ（"写真"、"画像"等）は禁止。具体的に。**
5. **出力は valid JSON のみ。それ以外のテキストは禁止。**

### タグのカテゴリ（タクソノミー）

| カテゴリ | 内容 | 例 |
|---------|------|-----|
| objects | 具体的な被写体 | 人物、猫、ラーメン、看板 |
| scene | 場所やシーンの種類 | レストラン、公園、海岸、街中 |
| attributes | 色、状態、特徴 | 赤い、雪景色、手書き、ネオン |
| mood | 雰囲気 | にぎやか、静か、レトロ、モダン |

### 出力スキーマ（v2: 構造化版）
```json
{
  "analysis": "画像の観察結果（CoTステップ。保存はしない）",
  "tags": {
    "objects": ["被写体1", "被写体2"],
    "scene": ["シーン"],
    "attributes": ["特徴"],
    "mood": ["雰囲気"]
  },
  "description": "1-2文の説明"
}
```

旧形式（v1: `{"tags": ["tag1", "tag2"], "description": "..."}`) も後方互換で対応。

## 統一プロンプト構成

| プロンプト | 用途 | 定義場所 |
|---|---|---|
| `TaggingPrompts.system` | システムプロンプト（タクソノミー定義・ルール・Few-shot例） | `LLMServiceProtocol.swift` |
| `TaggingPrompts.userPromptForOCR()` | OCRテキストからのタグ抽出（CoT指示付き） | `LLMServiceProtocol.swift` |
| `TaggingPrompts.userPromptForImage` | 画像からの直接タグ抽出（CoT指示付き） | `LLMServiceProtocol.swift` |
| `TaggingPrompts.parseJSONResponse()` | JSON応答の共通パース処理（v1/v2両対応） | `LLMServiceProtocol.swift` |

## サービス対応表

| サービス | モデル | 入力 | 使用プロンプト |
|---|---|---|---|
| CloudLLMService | Claude API | OCRテキスト / 画像 | system + userPromptForOCR / userPromptForImage |
| AppleFoundationModelsService | Apple Intelligence | OCRテキスト | system + userPromptForOCR |
| LlamaService | Gemma 2B (ローカル) | OCRテキスト | userPromptForOCR（Gemma Instruct形式でラップ） |
| VLMService | MiniCPM-V (ローカル) | 画像 | userPromptForImage |

## パイプライン全体フロー

詳細は [IMAGE_TAGGING_PIPELINE.md](IMAGE_TAGGING_PIPELINE.md) を参照。

```
Phase 1: EXIF メタデータ → タグ（カメラ・季節・時間帯・場所）
Phase 2: 画像ベースAI（Cloud API → VLM）→ 構造化タグ
Phase 3: OCRテキスト抽出（常に実行） → ハッシュタグ・キーワード即タグ化
Phase 4: OCR+LLMフォールバック（画像AIが使えない場合のみ）
Phase 5: 後処理（バリデーション・同義語正規化）→ 保存
```

## タグ品質保証

### 入力品質
- OCR信頼度フィルタ（confidence < 0.3 除外）
- 画像前処理（コントラスト・シャープネス補正）
- OCR品質ゲート（10文字未満 or 文字率30%未満 → LLMに渡さない）

### 出力品質
- タグバリデーション（2〜20文字、文字種チェック、ゴミパターン除外）
- 同義語正規化（英日変換、カタカナ/漢字統一、類義語マージ）
- Chain-of-Thoughtでハルシネーション抑制
- タグ保存時に `lowercased()` + `trim` で正規化
- CoreData側で同名タグは既存エンティティを再利用（find-or-create）
