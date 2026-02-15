# MacPhotoBrowser 仕様

## 0. 目的と前提
- 目的：画像を「取り込み」「閲覧（ブラウズ）」「アルバム／タグで整理」できるアプリ
- プラットフォーム：macOS（Mac Catalyst）
- 実装：Swift / SwiftUI
- アーキテクチャ：Clean Architecture（Domain / Data / Presentation）、MVVM

---

## 1. UI構成

### 1.1 全体レイアウト
- `NavigationSplitView`（`.balanced` スタイル）でサイドバー＋詳細の2カラム構成
- macOS 公式写真アプリに近いUI

### 1.2 サイドバー
- **ライブラリ** — 全画像のグリッド表示
- **検索** — タグ検索
- **マイアルバム** — アルバム一覧（作成・削除可能）
- **タグ** — タグ一覧（写真数バッジ付き）
- サイドバーの表示/非表示を切り替え可能（`Cmd+Ctrl+S`）
- アルバム・タグへの**ドラッグ&ドロップ**で写真を追加可能

### 1.3 写真グリッド
- `LazyVGrid` による3カラムグリッド
- シングルクリック：写真を選択（青い枠でハイライト）
- ダブルクリック：詳細画面へ遷移
- ドラッグでサイドバーのアルバム/タグに追加可能

### 1.4 詳細画面
- **ズーム可能な画像領域**（`scaleEffect` + `MagnifyGesture` + `DragGesture`）
  - ピンチ/トラックパッドでズーム（0.5x〜5.0x）
  - ダブルタップで原寸⇔2.5xの切り替え
  - ズーム時はドラッグでパン操作
- **ズームスライダーバー**（−/+ボタン、スライダー、1:1リセット、%表示）
- **情報セクション**（スクロール可能）
  - AI分析（タグ・説明文の自動生成）
  - タグ（追加・削除）
  - アルバム（追加・削除）
  - メタデータ（ファイル名、サイズ、撮影日時、カメラ情報等）
  - OCR抽出テキスト（コピー可能）

---

## 2. データ管理

### 2.1 取り込みソース
- Photos（写真アプリ）
- Files（ファイルアプリ／iCloud Drive等）

### 2.2 取り込み処理
- 画像のユニークID付与
- サムネイル生成
- アプリ内にコピーして管理
- EXIF読み取り（撮影日時、サイズ、カメラ情報、GPS等）

### 2.3 ローカルデータ管理
- Core Data
  - ImageEntity：画像ID、保存先、撮影日時、サイズ、メタデータ、AI説明文、OCRテキスト
  - TagEntity：タグ名、作成日時
  - AlbumEntity：アルバム名、作成日時
  - 多対多リレーション（画像⇔タグ、画像⇔アルバム）
- サムネイルキャッシュ（`ThumbnailCache`）

---

## 3. AI機能

### 3.1 自動タグ付け・説明文生成
- `AutoTaggingService` がエントリーポイント
- 処理の流れ：OCRテキスト抽出 → 最適なLLMでタグ・説明文を生成
- フォールバック：クラウドAPI → VLM → OCR+LLM
- タグは3〜5個に厳選、類似タグの重複を回避

### 3.2 対応LLMサービス
- **CloudLLMService** — Claude API（クラウド、最高精度）
- **VLMService** — MiniCPM-V（ローカル、画像直接入力）
- **AppleFoundationModelsService** — Apple Intelligence（iOS 26+）
- **LlamaService** — Gemma 2B（ローカル、OCRテキスト入力）

### 3.3 OCR
- Vision framework によるテキスト抽出
- 抽出テキストはDBに保存し検索対象に含める

詳細は [AI_PROMPTS.md](AI_PROMPTS.md) および [VLM_INTEGRATION.md](VLM_INTEGRATION.md) を参照。

---

## 4. データ整合性

- タグ/アルバムの変更は `NotificationCenter` で全画面に伝播
  - `.tagsDidChange` / `.albumsDidChange`
  - DetailView, ContentView（ドラッグ&ドロップ）, AlbumDetailView で変更をポスト
  - TagsViewModel, AlbumsViewModel, AlbumDetailViewModel, TagImagesView で受信してリロード

---

## 5. 画面一覧

| 画面 | ファイル | 概要 |
|------|---------|------|
| メイン | `ContentView.swift` | サイドバー + 詳細の2カラム |
| ライブラリ | `LibraryView.swift` | 全写真のグリッド表示 |
| 詳細 | `DetailView.swift` | ズーム対応画像 + 情報セクション |
| アルバム詳細 | `AlbumDetailView.swift` | アルバム内写真のグリッド |
| タグ写真 | `TagsListView.swift` | タグに紐づく写真のグリッド |
| 検索 | `SearchView.swift` | タグ検索と結果グリッド |
| インポート | `ImportView.swift` | 写真の取り込み |
| 設定 | `SettingsView.swift` | アプリ設定 |
| LLM設定 | `LLMSettingsView.swift` | AIモデルの設定・管理 |

---

## 6. 依存関係注入

- `DependencyContainer`（シングルトン）で各Repository・ViewModelを生成
- リポジトリ：`ImageRepository`, `TagRepository`, `AlbumRepository`
- 各ViewModelはコンストラクタインジェクションで依存を受け取る
