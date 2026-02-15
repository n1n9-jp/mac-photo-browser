# AI プロンプト一覧

本プロジェクトでは、写真の自動タグ付けと説明文生成を目的として、複数のAIモデルを利用しています。

## プロンプト設計方針

全モデルで **同一スキーマ・同一出力制約** の統一プロンプトを使用しています（`TaggingPrompts` enum in `LLMServiceProtocol.swift`）。

### 基本ルール
1. **写真の内容を正確に分析。推測は最小限。**
2. **日本語でタグと説明を生成。**
3. **タグは3〜5個に厳選。意味が重なるタグは1つにまとめる。**
4. **抽象的すぎるタグ（"写真"、"画像"等）は禁止。**
5. **出力は valid JSON のみ。それ以外のテキストは禁止。**

### 出力スキーマ（全モデル共通）
```json
{"tags": ["風景", "海", "夕焼け"], "description": "写真の簡潔な説明"}
```

## 統一プロンプト構成

| プロンプト | 用途 | 定義場所 |
|---|---|---|
| `TaggingPrompts.system` | システムプロンプト（詳細なタグ付けルール） | `LLMServiceProtocol.swift` |
| `TaggingPrompts.userPromptForOCR()` | OCRテキストからのタグ抽出 | `LLMServiceProtocol.swift` |
| `TaggingPrompts.userPromptForImage` | 画像からの直接タグ抽出 | `LLMServiceProtocol.swift` |
| `TaggingPrompts.parseJSONResponse()` | JSON応答の共通パース処理 | `LLMServiceProtocol.swift` |

## サービス対応表

| サービス | モデル | 入力 | 使用プロンプト |
|---|---|---|---|
| CloudLLMService | Claude API | OCRテキスト / 画像 | system + userPromptForOCR / userPromptForImage |
| AppleFoundationModelsService | Apple Intelligence | OCRテキスト | userPromptForOCR |
| LlamaService | Gemma 2B (ローカル) | OCRテキスト | userPromptForOCR（Gemma Instruct形式でラップ） |
| VLMService | MiniCPM-V (ローカル) | 画像 | userPromptForImage |

## フォールバックの流れ

`AutoTaggingService.processImage(imageId:image:)` → `LLMService.extractTagsBestMethod()`:

1. **クラウドAPI** が利用可能 → 画像から直接タグ抽出（最高精度）
2. **VLM** が利用可能 → 画像から直接タグ抽出
3. **OCR+LLM** → OCRテキストからLLMでタグ抽出
4. いずれも利用不可 → 抽出なし

## タグ重複防止

- プロンプトで「意味が重なるタグは1つにまとめる」と指示
- タグ保存時に名前を `lowercased()` + `trimmingCharacters` で正規化
- CoreData側で同名タグは既存エンティティを再利用（`addTag` で find-or-create）
