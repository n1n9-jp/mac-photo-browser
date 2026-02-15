# プラットフォーム戦略

## 現状

- **ビルドシステム**: iOS SDK + Mac Catalyst (`SUPPORTS_MACCATALYST = YES`)
- **UI フレームワーク**: SwiftUI + UIKit
- **ターゲット**: iPhone / iPad (`TARGETED_DEVICE_FAMILY = 1,2`) + macOS (Catalyst)

Mac Catalyst により、**単一コードベースで macOS と iOS の両方にビルド可能**。
macOS 用のビルドは Catalyst 経由で動作し、iOS 実機ビルドは iOS SDK のインストールで対応可能。

## なぜ Mac Catalyst か

| 観点 | Mac Catalyst | ネイティブ macOS (AppKit) |
|------|-------------|--------------------------|
| iOS/macOS コード共有率 | ~100% | 低い（UIKit/AppKit が別API） |
| 開発・保守コスト | 1アプリ分 | 実質2アプリ分 |
| macOS らしい操作感 | やや iOS 的（SwiftUI で改善可） | 最もネイティブ |
| macOS 固有機能 | NSToolbar 等は一部利用可能 | フルアクセス |
| パフォーマンス | UIKit 互換レイヤー経由 | 直接描画 |
| 配布 | App Store / TestFlight | App Store / 直接配布 |

本アプリは SwiftUI 主体で構築されており、Catalyst でも十分な macOS UX が得られる。
iOS との両対応を維持することが最優先のため、**Mac Catalyst が最適な選択**。

## プラットフォーム互換性

すべての主要依存が macOS / iOS 両方で動作することを確認済み。

| コンポーネント | macOS (Catalyst) | iOS |
|---------------|-----------------|-----|
| SwiftUI | OK | OK |
| UIKit | OK (Catalyst 互換) | OK |
| CoreData | OK | OK |
| Vision (OCR) | OK | OK |
| Photos / PHPicker | OK | OK |
| CoreLocation (逆ジオコーディング) | OK | OK |
| FoundationModels (Apple Intelligence) | macOS 26+ / M1以降 | iOS 26+ / A17 Pro以降 |
| llama.xcframework (VLM) | Catalyst スライスあり | iOS スライスあり |
| NaturalLanguage (NLTagger) | OK | OK |
