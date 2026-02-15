# VLM (Vision Language Model) 統合ドキュメント

## 概要

本の表紙画像から直接書籍情報（タイトル、著者、ISBN等）を抽出するVision Language Model (VLM) の統合。

**ステータス: ✅ 統合完了（2024-02-06）**

## 現在の状況

### 試行した方法

#### 1. LocalLLMClient (Swift Package Manager)
- **リポジトリ**: https://github.com/tattn/LocalLLMClient
- **結果**: 失敗
- **原因**: Xcode SPMがgitサブモジュール（llama.cpp）を解決できない
- **エラー**: `Couldn't update repository submodules`

#### 2. StanfordBDHG/llama.cpp (Swift Package Manager)
- **リポジトリ**: https://github.com/StanfordBDHG/llama.cpp
- **結果**: ビルド成功（テキストLLM用）
- **制限**: VLM（マルチモーダル）機能は含まれていない

### 現在の実装状態 ✅ 統合完了

- `VLMService.swift` - MTMDWrapperを使用した実装完了
- `VLMServiceProtocol` - 定義済み
- `LLMService` - VLM統合済み（VLM優先、OCR+LLMにフォールバック）
- `OCRService` - VLM対応済み
- `LLMSettingsView` - VLMセクション有効化（モデルダウンロード案内付き）
- `llama.xcframework` - MiniCPM-o-demo-iOSからコピー済み
- `MTMDWrapper` - Swift-Cブリッジコピー済み

## 解決策: MiniCPM-o-demo-iOS からの直接統合

### アプローチ

MiniCPM-o-demo-iOS プロジェクトから以下をコピーして統合:

1. **llama.xcframework** (VLM対応版)
   - 場所: `~/Desktop/MiniCPM-o-demo-iOS/MiniCPM-V-demo/thirdparty/llama.xcframework`
   - サイズ: 約50MB
   - 対応プラットフォーム: iOS, iOS Simulator, macOS, tvOS, visionOS

2. **MTMDWrapper** (Swift-C ブリッジ)
   - 場所: `~/Desktop/MiniCPM-o-demo-iOS/MiniCPM-V-demo/MTMDWrapper/`
   - 機能: llama.cpp の C API を Swift から呼び出すラッパー

### 統合手順 ✅ 完了

1. ✅ `thirdparty/` フォルダを作成し、`llama.xcframework` をコピー
2. ✅ Xcode プロジェクトに xcframework を追加
3. ✅ `MTMDWrapper` コードをコピー・修正
4. ✅ `VLMService` を実際の実装に更新
5. ✅ 設定画面の「準備中」表示を解除

### 必要なモデルファイル

VLMを使用するには以下のモデルファイルが必要（ユーザーがダウンロード）:

- **言語モデル**: `ggml-model-Q4_0.gguf` (~2.08GB)
- **ビジョンエンコーダ**: `mmproj-model-f16.gguf` (~960MB)
- **ダウンロード元**: https://huggingface.co/openbmb/MiniCPM-V-4-gguf

### メリット

- Swift Package Manager の問題を回避
- MiniCPM-o-demo-iOS で動作実績あり
- 完全にオンデバイスで動作

### デメリット

- アプリサイズ増加（xcframework: ~50MB）
- モデルファイルは別途ダウンロード必要（~3GB）
- フレームワークの更新は手動

## 参考リンク

- [MiniCPM-o-demo-iOS](https://github.com/tc-mb/MiniCPM-o-demo-iOS)
- [MiniCPM-V-4-gguf (HuggingFace)](https://huggingface.co/openbmb/MiniCPM-V-4-gguf)
- [LocalLLMClient](https://github.com/tattn/LocalLLMClient)

## アーキテクチャ全体図

### サービス構成

```
OCRService (エントリーポイント: extractBookInfoBestEffort)
    ↓
LLMService (ファサード・ルーター)
    ├── VLMService          … 画像 → 書籍情報（OCR不要）
    ├── AppleFoundationModelsService … OCRテキスト → 書籍情報（iOS 26+）
    └── LlamaService        … OCRテキスト → 書籍情報（llama.cpp）
```

### フォールバックの流れ

`OCRService.extractBookInfoBestEffort(from:)` 内での処理順序:

1. **VLM** が利用可能 → 画像から直接抽出 → 成功し有効データがあれば返す（ISBNがなければOCRで補完）
2. VLM失敗 or 利用不可 → **OCR実行**（Vision framework、iOS 26+ならApple Intelligenceで自動補正）
3. **LLM** が利用可能 → OCRテキストから構造化データを抽出
   - autoモード: Apple Intelligence → Llama の順で試行
   - ISBNがなければ正規表現で補完
4. LLM利用不可 → **正規表現**でISBNのみ抽出

### 各サービスの比較

| サービス | 入力 | 処理方式 | 利用条件 | ダウンロード |
|---------|------|---------|---------|------------|
| VLMService | UIImage | 画像直接処理 (MiniCPM-V 4.0) | モデルダウンロード済み | 必要 (~3GB) |
| AppleFoundationModelsService | OCRテキスト | Apple Foundation Models | iOS 26+ / A17 Pro以上 | 不要 |
| LlamaService | OCRテキスト | llama.cpp (Gemma 2B) | モデルダウンロード済み | 必要 (~1.5GB) |
| OCRService | UIImage | Vision framework OCR | 常時利用可能 | 不要 |

## プロンプト設計

### VLM用プロンプト (`makeVLMBookExtractionPrompt`)

`VLMService.swift` で定義。画像を直接入力とするため、OCRテキストは不要。

```
この画像は本の表紙です。書籍情報を抽出してJSON形式で出力してください。

出力形式（JSONのみ、説明不要）:
{"title": "書籍タイトル", "author": "著者名", "publisher": "出版社名", "isbn": "ISBN13桁"}

注意:
- 見つからない項目はnull
- タイトルと著者名を正確に読み取ってください
- 日本語の場合は日本語で出力
```

### VLM生成パラメータ

| パラメータ | 値 | 説明 |
|-----------|-----|------|
| nPredict | 512 | 最大生成トークン数（書籍情報抽出には十分） |
| nCtx | 4096 | コンテキスト長 |
| nThreads | 4 | CPUスレッド数 |
| temperature | 0.3 | 低温度で安定した出力を得る |
| useGPU | true | GPU使用（Metal） |
| mmprojUseGPU | true | ビジョンエンコーダもGPU使用 |
| warmup | true | 初回推論前のウォームアップ |

### OCR+LLM用プロンプト (`makeBookExtractionPrompt`)

`LLMServiceProtocol.swift` で定義。Apple Intelligence / Llama 共通で使用。

```
以下は本の表紙や奥付からOCRで読み取ったテキストです。
書籍情報を抽出してJSON形式で出力してください。

OCRテキスト:
[OCRテキストがここに挿入される]

出力形式（JSONのみ、説明不要）:
{
  "title": "書籍タイトル",
  "author": "著者名",
  "publisher": "出版社名",
  "isbn": "ISBN-13（13桁の数字のみ）"
}

注意:
- ISBNは数字のみ13桁（978または979で始まる）
- 見つからない項目はnull
- OCRの誤認識（0とO、1とIやl）を考慮して推測
- タイトルや著者名の明らかな誤字は修正
```

### VLMプロンプトとOCR+LLMプロンプトの違い

| | VLMプロンプト | OCR+LLMプロンプト |
|---|---|---|
| 入力 | 画像（表紙そのもの） | OCRで読み取ったテキスト |
| OCR誤認識への対処 | 不要（画像を直接認識） | 「0とO、1とIやl」の誤認識を考慮するよう指示 |
| ISBN形式の指示 | 「ISBN13桁」 | 「13桁の数字のみ（978/979で始まる）」とより具体的 |
| 誤字修正 | なし | 「明らかな誤字は修正」を指示 |

### JSONレスポンスのパース処理

VLM / Apple Intelligence / Llama いずれも同様のパース処理を行う:

1. マークダウンコードブロック（` ```json ... ``` `）の除去
2. 最初の `{` から最後の `}` までを抽出
3. `JSONSerialization` でパース → `ExtractedBookData` に変換
4. ISBNクリーニング（数字のみ抽出、13桁でなければ破棄）
5. 信頼度スコア計算（抽出できたフィールド数に基づく 0.0〜1.0）

Apple Intelligence のみ、JSONパース失敗時に正規表現でプレーンテキストからの抽出を試みるフォールバックあり。

## Apple Intelligence連携

### 概要

`AppleFoundationModelsService` は Apple の `FoundationModels` フレームワークを使用したLLMサービス。

- **対応OS**: iOS 26以降
- **対応チップ**: A17 Pro以上
- **ダウンロード**: 不要（システム内蔵）
- **使用量制限**: オンデバイス処理のため、明確な使用量制限なし

### 実装

```swift
#if canImport(FoundationModels)
import FoundationModels
#endif

// LanguageModelSession を使用して推論
let session = LanguageModelSession()
let response = try await session.respond(to: prompt)
```

### LLMServiceでの優先度

`LLMEnginePreference` 設定に基づいてルーティング:

- **`.auto`（推奨）**: Apple Intelligence → Llama の順で試行
- **`.appleIntelligence`**: Apple Intelligenceのみ使用
- **`.localModel`**: Llamaのみ使用
- **`.none`**: LLMを使用しない

### OCR補正での利用

iOS 26以降では `OCRService.recognizeTextWithCorrection(from:)` 内で Apple Intelligence を使ったOCR補正も行う。OCR結果の誤認識（0↔O、1↔I/l など）を自動修正してからLLMに渡す。

### フォールバック処理

JSONパース失敗時、正規表現で以下のパターンを抽出:
- タイトル: `タイトル：xxx` / `title: xxx`
- 著者: `著者：xxx` / `author: xxx`
- ISBN-13: `97[89]\d{10}`

この場合の信頼度スコアは `0.3`（低信頼度）に設定される。

## 使用方法

### モデルファイルのインストール

1. [HuggingFace](https://huggingface.co/openbmb/MiniCPM-V-4-gguf) からモデルをダウンロード:
   - `ggml-model-Q4_0.gguf` (~2.08GB)
   - `mmproj-model-f16-iOS.gguf` (~960MB)

2. ファイルをiOSデバイスの Documents/VLMModels/ ディレクトリに配置

3. アプリの「設定 > AI処理」でモデルの認識を確認

### 動作確認

VLMが有効な場合、詳細画面の「書誌情報を抽出」ボタンをタップすると:
1. まずVLMで画像から直接書籍情報を抽出
2. VLMが失敗した場合、OCR+テキストLLMにフォールバック

## 完了した作業の詳細

### 1. llama.xcframework のコピー

```
コピー元: ~/Desktop/MiniCPM-o-demo-iOS/MiniCPM-V-demo/thirdparty/llama.xcframework
コピー先: MacPhotoBrowser/MacPhotoBrowser/thirdparty/llama.xcframework
```

含まれるプラットフォーム:
- ios-arm64
- ios-arm64_x86_64-simulator
- macos-arm64_x86_64
- tvos-arm64
- tvos-arm64_x86_64-simulator
- xros-arm64
- xros-arm64_x86_64-simulator

### 2. MTMDWrapper のコピー・統合

```
コピー先: MacPhotoBrowser/MacPhotoBrowser/Services/VLM/MTMDWrapper/
```

ファイル構成:
- `MTMDWrapper.swift` - メインのラッパークラス（@MainActor）
- `MTMDParams.swift` - 初期化パラメータ構造体
- `MTMDToken.swift` - トークン・生成状態の定義
- `MTMDError.swift` - エラー型の定義

### 3. Xcodeプロジェクトの変更

`project.pbxproj` への変更:
- StanfordBDHG/llama.cpp Swift Package を削除
- llama.xcframework をFrameworksグループに追加
- "Embed Frameworks" ビルドフェーズを追加
- フレームワークをリンク・埋め込み設定

### 4. VLMService の実装

`MacPhotoBrowser/Services/LLM/VLMService.swift`:
- MTMDWrapperを使用した画像からの書籍情報抽出
- 画像を一時ファイルに保存してMTMDWrapperに渡す
- JSON形式のレスポンスをパースしてExtractedBookDataを返す
- VLMModelManagerでモデルファイルの状態を管理

### 5. LlamaService の更新

新しいllama.cpp APIへの対応:
- `llama_batch_add` / `llama_batch_clear` → 直接構造体操作に変更
- `llama_n_vocab` → `llama_vocab_n_tokens` に変更
- `llama_token_is_eog` → `llama_vocab_is_eog` に変更
- `llama_tokenize` → vocab引数を使用するように変更
- `llama_token_to_piece` → 6引数のシグネチャに対応

### 6. 設定画面の更新

`MacPhotoBrowser/Presentation/Settings/LLMSettingsView.swift`:
- VLMモデルの状態表示（ダウンロード済み/未ダウンロード）
- HuggingFaceへのダウンロードリンク
- VLMモデル削除機能
- LLMInfoViewのVLM説明を更新

## ファイル構成

```
MacPhotoBrowser/
├── MacPhotoBrowser/
│   ├── thirdparty/
│   │   └── llama.xcframework/          # VLM対応フレームワーク
│   └── Services/
│       ├── LLM/
│       │   ├── LLMService.swift        # LLMファサード
│       │   ├── LLMServiceProtocol.swift
│       │   ├── LlamaService.swift      # テキストLLM
│       │   ├── VLMService.swift        # 画像→書籍情報抽出
│       │   ├── LLMModelManager.swift
│       │   └── AppleFoundationModelsService.swift
│       └── VLM/
│           └── MTMDWrapper/
│               ├── MTMDWrapper.swift
│               ├── MTMDParams.swift
│               ├── MTMDToken.swift
│               └── MTMDError.swift
└── docs/
    └── VLM_INTEGRATION.md              # このドキュメント
```

## 更新履歴

- 2024-02-06: LocalLLMClient 統合試行 → 失敗
- 2024-02-06: 直接統合アプローチに切り替え決定
- 2024-02-06: VLM統合完了 ✅
  - llama.xcframework をMiniCPM-o-demo-iOSからコピー
  - MTMDWrapper をコピー・統合
  - VLMService を実装
  - LLMSettingsView でVLMセクション有効化
  - LlamaService を新しいllama.cpp APIに対応
  - ビルド成功確認済み
