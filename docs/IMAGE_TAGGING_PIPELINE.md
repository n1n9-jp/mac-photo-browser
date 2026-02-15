# 画像タグ付けパイプライン設計書

## 概要

写真のインポート時（または手動実行時）に、画像データから構造化された情報を抽出し、
検索・整理に活用可能なタグと説明文を自動生成するパイプライン。

---

## パイプライン全体フロー

```
┌─────────────────────────────────────────────────────────────────┐
│  ImportImageUseCase / DetailViewModel.runAITagging()            │
│  → AutoTaggingService.processImage(imageId, image, metadata)   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 1: EXIF メタデータからタグ生成（即時）                      │
│  ─ カメラ機種 → "iphone", "canon" 等                             │
│  ─ 撮影日時 → 季節（春/夏/秋/冬）＋ 時間帯（早朝/朝/夕方/夜/深夜）  │
│  ─ GPS座標 → 逆ジオコーディング → 市区町村名                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 2: 画像ベースAI抽出（最優先）                              │
│                                                                 │
│  ┌─ 2a. Cloud API（Claude）画像入力                              │
│  │   精度: ★★★★★  条件: APIキー設定済み                          │
│  │   入力: UIImage → JPEG base64 (max 1024px)                   │
│  │   プロンプト: CoT + 構造化タクソノミー + Few-shot               │
│  │   出力: 構造化JSON                                            │
│  │                                                              │
│  └─ 2b. VLM（MiniCPM-V 4.0）ローカル画像入力                     │
│      精度: ★★★★☆  条件: モデルダウンロード済み (~3GB)              │
│      入力: UIImage → JPEG temp file                              │
│      プロンプト: CoT + 構造化タクソノミー + Few-shot               │
│      出力: 構造化JSON                                            │
│                                                                 │
│  → いずれかが成功したら imageBasedSuccess = true                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 3: OCRテキスト抽出（常に実行、保存用）                      │
│                                                                 │
│  3a. 画像前処理                                                  │
│      ─ EXIF向き正規化                                            │
│      ─ CIColorControls: コントラスト 1.15                        │
│      ─ CISharpenLuminance: シャープネス 0.4                      │
│                                                                 │
│  3b. VNRecognizeTextRequest（日本語・英語、confidence ≥ 0.3）     │
│                                                                 │
│  3c. Apple Intelligence補正（iOS 26+: OCR誤認識を自動修正）       │
│                                                                 │
│  3d. 抽出テキストをDBに保存（全文検索用）                          │
│                                                                 │
│  3e. ハッシュタグ検出 → 即タグ化（#タグ / ＃タグ 対応）            │
│                                                                 │
│  3f. NLTagger キーワード抽出 → 名詞・固有名詞を即タグ化（上位5個）  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 4: OCR+LLM フォールバック（画像ベースAI失敗時のみ）         │
│                                                                 │
│  条件: imageBasedSuccess == false                                │
│        && OCRテキストが品質ゲート通過（≥10文字, 文字率>30%）       │
│                                                                 │
│  LLM優先順位（auto設定時）:                                       │
│  1. Cloud API (Claude) テキスト入力                               │
│  2. Apple Intelligence (iOS 26+)                                │
│  3. Local LLM (Gemma 2B)                                        │
│                                                                 │
│  プロンプト: CoT + 構造化タクソノミー + Few-shot（OCRテキスト版）   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 5: 後処理・保存                                           │
│                                                                 │
│  5a. タグバリデーション                                           │
│      ─ 2〜20文字                                                 │
│      ─ 文字（ひらがな/カタカナ/漢字/英字）を含む                    │
│      ─ ゴミパターン除外（"タグ", "unknown", "写真" 等）            │
│                                                                 │
│  5b. 同義語正規化                                                │
│      ─ 日英同義語マッピング（"cat"→"猫", "ocean"→"海" 等）        │
│      ─ 表記揺れ統一（カタカナ/漢字の揺れ: "ネコ"→"猫"）           │
│      ─ 重複除去                                                  │
│                                                                 │
│  5c. タグ保存（lowercased + trim、find-or-create）               │
│                                                                 │
│  5d. 説明文保存                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## プロンプト設計

### 設計原則（gemini.pdf ベストプラクティス準拠）

1. **構造化タクソノミー** — フラットなタグリストではなく、カテゴリ別に要求
2. **Chain-of-Thought (CoT)** — まず画像を観察・分析し、その後タグを生成（ハルシネーション抑制）
3. **Few-shot 例** — 具体的な入出力例を提示してフォーマットと品質を安定化
4. **JSON厳守** — 全モデル共通のスキーマで出力

### 出力スキーマ（v2: 構造化版）

```json
{
  "analysis": "画像の観察結果を1-2文で記述（CoTステップ）",
  "tags": {
    "objects": ["被写体1", "被写体2"],
    "scene": ["シーン/場所の種類"],
    "attributes": ["色・特徴・状態"],
    "mood": ["雰囲気"]
  },
  "description": "写真全体の簡潔な説明（1-2文）"
}
```

最終的にタグとして保存されるのは `objects + scene + attributes + mood` を結合したフラットリスト。
`analysis` はタグ生成精度向上のためのCoTステップであり、保存はしない。

### プロンプト一覧

| プロンプト | 用途 | 使用サービス |
|---|---|---|
| `TaggingPrompts.system` | システムプロンプト（タクソノミー定義・ルール・Few-shot例） | Cloud API, Apple Intelligence |
| `TaggingPrompts.userPromptForImage` | 画像からの直接抽出（CoT指示付き） | Cloud API (画像), VLM |
| `TaggingPrompts.userPromptForOCR()` | OCRテキストからの抽出（CoT指示付き） | Cloud API (テキスト), Apple Intelligence, Gemma 2B |

---

## サービス構成

```
AutoTaggingService (オーケストレーター)
    │
    ├── OCRService (テキスト抽出)
    │     ├── 画像前処理 (CIFilter)
    │     ├── VNRecognizeTextRequest (Vision)
    │     └── Apple Intelligence補正 (iOS 26+)
    │
    └── LLMService (ファサード・ルーター)
          ├── CloudLLMService     … Claude API（画像/テキスト → 構造化タグ）
          ├── VLMService          … MiniCPM-V 4.0（画像 → 構造化タグ、ローカル）
          ├── AppleFoundationModelsService … Apple Intelligence（テキスト → タグ、iOS 26+）
          └── LlamaService        … Gemma 2B（テキスト → タグ、ローカル）
```

### 各サービスの比較

| サービス | 入力 | 精度 | 条件 | 通信 | ダウンロード |
|---------|------|------|------|------|------------|
| CloudLLMService | 画像 / テキスト | ★★★★★ | APIキー | 必要 | 不要 |
| VLMService | 画像 | ★★★★☆ | モデルDL | 不要 | ~3GB |
| AppleFoundationModelsService | テキスト | ★★★☆☆ | iOS 26+ | 不要 | 不要 |
| LlamaService | テキスト | ★★☆☆☆ | モデルDL | 不要 | ~1.5GB |

---

## 品質保証メカニズム

### 入力品質

| チェック | 内容 | 適用箇所 |
|---------|------|---------|
| OCR信頼度フィルタ | confidence < 0.3 のテキストを除外 | OCRService |
| 画像前処理 | コントラスト・シャープネス補正、向き正規化 | OCRService |
| OCR品質ゲート | 10文字未満 or 文字率30%未満 → LLMに渡さない | AutoTaggingService |

### 出力品質

| チェック | 内容 | 適用箇所 |
|---------|------|---------|
| タグバリデーション | 文字数制限、文字種チェック、ゴミパターン除外 | AutoTaggingService |
| 同義語正規化 | 日英・表記揺れ統一、重複除去 | AutoTaggingService |
| CoTプロンプティング | 「まず観察→次にタグ生成」でハルシネーション抑制 | TaggingPrompts |

---

## 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `Services/LLM/LLMServiceProtocol.swift` | TaggingPrompts: 構造化タクソノミー + CoT + Few-shot、ExtractedTagData拡張、parseJSONResponse v2対応 |
| `Services/LLM/CloudLLMService.swift` | 画像リサイズ 1568→1024px |
| `Services/AutoTaggingService.swift` | 同義語正規化テーブル追加 |

---

## 今後の拡張候補（未実装）

- **タグ階層構造**: DB設計変更が必要（`猫 > 動物` のような親子関係）
- **埋め込みベクトル検索**: 類似画像・意味検索（アーキテクチャ変更大）
- **外部API連携**: Google Maps API で店名・スポットをエンティティ解決
