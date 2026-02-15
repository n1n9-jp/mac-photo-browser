# VLM (Vision Language Model) 統合ドキュメント

## 概要

写真から直接タグと説明文を抽出するVision Language Model (VLM) の統合。

**ステータス: 統合完了**

## 現在の状況

### 試行した方法

#### 1. LocalLLMClient (Swift Package Manager)
- **リポジトリ**: https://github.com/tattn/LocalLLMClient
- **結果**: 失敗
- **原因**: Xcode SPMがgitサブモジュール（llama.cpp）を解決できない

#### 2. StanfordBDHG/llama.cpp (Swift Package Manager)
- **リポジトリ**: https://github.com/StanfordBDHG/llama.cpp
- **結果**: ビルド成功（テキストLLM用）
- **制限**: VLM（マルチモーダル）機能は含まれていない

### 現在の実装状態

- `VLMService.swift` - MTMDWrapperを使用した実装完了
- `VLMServiceProtocol` - 定義済み
- `LLMService` - VLM統合済み（クラウドAPI → VLM → OCR+LLMのフォールバック）
- `OCRService` - VLM対応済み
- `LLMSettingsView` - VLMセクション有効化（モデルダウンロード案内付き）
- `llama.xcframework` - MiniCPM-o-demo-iOSからコピー済み
- `MTMDWrapper` - Swift-Cブリッジコピー済み

## 解決策: MiniCPM-o-demo-iOS からの直接統合

### アプローチ

MiniCPM-o-demo-iOS プロジェクトから以下をコピーして統合:

1. **llama.xcframework** (VLM対応版)
   - サイズ: 約50MB
   - 対応プラットフォーム: iOS, iOS Simulator, macOS, tvOS, visionOS

2. **MTMDWrapper** (Swift-C ブリッジ)
   - 機能: llama.cpp の C API を Swift から呼び出すラッパー

### 必要なモデルファイル

VLMを使用するには以下のモデルファイルが必要（ユーザーがダウンロード）:

- **言語モデル**: `ggml-model-Q4_0.gguf` (~2.08GB)
- **ビジョンエンコーダ**: `mmproj-model-f16.gguf` (~960MB)
- **ダウンロード元**: https://huggingface.co/openbmb/MiniCPM-V-4-gguf

## アーキテクチャ

### サービス構成

```
AutoTaggingService (エントリーポイント: processImage)
    ↓
LLMService (ファサード・ルーター: extractTagsBestMethod)
    ├── CloudLLMService     … 画像 → タグ・説明文（Claude API、最高精度）
    ├── VLMService          … 画像 → タグ・説明文（ローカルVLM、OCR不要）
    ├── AppleFoundationModelsService … OCRテキスト → タグ・説明文（iOS 26+）
    └── LlamaService        … OCRテキスト → タグ・説明文（llama.cpp）
```

### フォールバックの流れ

`LLMService.extractTagsBestMethod(image:ocrText:)` 内での処理順序:

1. **クラウドAPI** が利用可能 → 画像から直接タグ抽出 → 成功すれば返す
2. **VLM** が利用可能 → 画像から直接タグ抽出
3. **OCRテキスト** があれば → LLMでタグ抽出（auto: クラウドAPI → Apple Intelligence → Llama）
4. いずれも利用不可 → 空のデータを返す

### 各サービスの比較

| サービス | 入力 | 処理方式 | 利用条件 | ダウンロード |
|---------|------|---------|---------|------------|
| CloudLLMService | UIImage / OCRテキスト | Claude API | APIキー設定済み | 不要 |
| VLMService | UIImage | 画像直接処理 (MiniCPM-V 4.0) | モデルダウンロード済み | 必要 (~3GB) |
| AppleFoundationModelsService | OCRテキスト | Apple Foundation Models | iOS 26+ / A17 Pro以上 | 不要 |
| LlamaService | OCRテキスト | llama.cpp (Gemma 2B) | モデルダウンロード済み | 必要 (~1.5GB) |
| OCRService | UIImage | Vision framework OCR | 常時利用可能 | 不要 |

## プロンプト設計

プロンプトの詳細は [AI_PROMPTS.md](AI_PROMPTS.md) を参照。

### VLM用プロンプト

画像を直接入力とするため、OCRテキストは不要。`TaggingPrompts.userPromptForImage` を使用。

### JSONレスポンスのパース処理

全サービス共通で `TaggingPrompts.parseJSONResponse()` を使用:

1. マークダウンコードブロック（` ```json ... ``` `）の除去
2. 最初の `{` から最後の `}` までを抽出
3. `JSONSerialization` でパース → `ExtractedTagData` に変換
4. 信頼度スコア計算（抽出できたタグ数に基づく 0.0〜1.0）

## Apple Intelligence連携

### 概要

`AppleFoundationModelsService` は Apple の `FoundationModels` フレームワークを使用したLLMサービス。

- **対応OS**: iOS 26以降
- **対応チップ**: A17 Pro以上
- **ダウンロード**: 不要（システム内蔵）

### LLMServiceでの優先度

`LLMEnginePreference` 設定に基づいてルーティング:

- **`.auto`（推奨）**: クラウドAPI → Apple Intelligence → Llama の順で試行
- **`.cloudAPI`**: クラウドAPIのみ使用
- **`.appleIntelligence`**: Apple Intelligenceのみ使用
- **`.localModel`**: Llamaのみ使用
- **`.none`**: LLMを使用しない

## ファイル構成

```
MacPhotoBrowser/
├── MacPhotoBrowser/
│   ├── thirdparty/
│   │   └── llama.xcframework/          # VLM対応フレームワーク
│   └── Services/
│       ├── AutoTaggingService.swift     # 自動タグ付けサービス
│       ├── OCRService.swift             # OCRサービス
│       ├── LLM/
│       │   ├── LLMService.swift         # LLMファサード
│       │   ├── LLMServiceProtocol.swift # プロトコル・プロンプト定義
│       │   ├── LlamaService.swift       # テキストLLM
│       │   ├── VLMService.swift         # 画像→タグ・説明文抽出
│       │   ├── LLMModelManager.swift    # モデル管理
│       │   └── AppleFoundationModelsService.swift
│       └── VLM/
│           └── MTMDWrapper/
│               ├── MTMDWrapper.swift
│               ├── MTMDParams.swift
│               ├── MTMDToken.swift
│               └── MTMDError.swift
└── docs/
    ├── AI_PROMPTS.md
    ├── VLM_INTEGRATION.md              # このドキュメント
    └── spec.md
```

## 参考リンク

- [MiniCPM-o-demo-iOS](https://github.com/tc-mb/MiniCPM-o-demo-iOS)
- [MiniCPM-V-4-gguf (HuggingFace)](https://huggingface.co/openbmb/MiniCPM-V-4-gguf)
