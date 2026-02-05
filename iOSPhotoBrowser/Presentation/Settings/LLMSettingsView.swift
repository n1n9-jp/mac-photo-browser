//
//  LLMSettingsView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct LLMSettingsView: View {
    @StateObject private var modelManager = LLMModelManager.shared
    @State private var enginePreference: LLMEnginePreference = .auto
    @State private var showingDeleteConfirmation = false
    @State private var showingDownloadConfirmation = false
    @State private var downloadError: String?
    @State private var showingError = false

    var body: some View {
        List {
            // MARK: - エンジン選択
            Section {
                Picker("LLMエンジン", selection: $enginePreference) {
                    ForEach(LLMEnginePreference.allCases, id: \.self) { preference in
                        VStack(alignment: .leading) {
                            Text(preference.displayName)
                        }
                        .tag(preference)
                    }
                }
                .onChange(of: enginePreference) { _, newValue in
                    modelManager.enginePreference = newValue
                }
            } header: {
                Text("AI処理設定")
            } footer: {
                Text(enginePreference.description)
            }

            // MARK: - Apple Intelligence
            Section {
                HStack {
                    Label("Apple Intelligence", systemImage: "apple.intelligence")
                    Spacer()
                    if #available(iOS 26.0, *) {
                        Text("利用可能")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("iOS 26以降")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("iOS 26以降のデバイスで、システムに組み込まれたAIを使用します。追加のダウンロードは不要です。")
            }

            // MARK: - ローカルモデル
            Section {
                HStack {
                    Label(LlamaService.ModelInfo.name, systemImage: "cpu")
                    Spacer()
                    if modelManager.isModelDownloaded {
                        Text("ダウンロード済み")
                            .foregroundStyle(.green)
                    } else {
                        Text("未ダウンロード")
                            .foregroundStyle(.secondary)
                    }
                }

                if modelManager.isModelDownloaded {
                    HStack {
                        Text("モデルサイズ")
                        Spacer()
                        Text(modelManager.displayDownloadedModelSize ?? "-")
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("モデルを削除", systemImage: "trash")
                    }
                } else if modelManager.isDownloading {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ダウンロード中...")
                            Spacer()
                            Text("\(Int(modelManager.downloadProgress * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: modelManager.downloadProgress)

                        Button(role: .destructive) {
                            modelManager.cancelDownload()
                        } label: {
                            Text("キャンセル")
                        }
                    }
                } else {
                    Button {
                        showingDownloadConfirmation = true
                    } label: {
                        Label("モデルをダウンロード", systemImage: "arrow.down.circle")
                    }

                    HStack {
                        Text("必要容量")
                        Spacer()
                        Text(LlamaService.ModelInfo.displayFileSize)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("ローカルモデル")
            } footer: {
                Text("オフラインでも動作するローカルAIモデルです。初回のみダウンロードが必要です。")
            }

            // MARK: - 情報
            Section {
                NavigationLink {
                    LLMInfoView()
                } label: {
                    Label("LLMについて", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("AI処理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            enginePreference = modelManager.enginePreference
        }
        .confirmationDialog(
            "モデルを削除しますか？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                deleteModel()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("モデルを削除すると、再度使用するにはダウンロードが必要です。")
        }
        .confirmationDialog(
            "モデルをダウンロードしますか？",
            isPresented: $showingDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("ダウンロード") {
                startDownload()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("約\(LlamaService.ModelInfo.displayFileSize)のダウンロードが必要です。Wi-Fi環境での実行を推奨します。")
        }
        .alert("エラー", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(downloadError ?? "不明なエラーが発生しました")
        }
    }

    private func startDownload() {
        Task {
            do {
                try await modelManager.startDownload()
            } catch {
                downloadError = error.localizedDescription
                showingError = true
            }
        }
    }

    private func deleteModel() {
        do {
            try modelManager.deleteModel()
        } catch {
            downloadError = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - LLM Info View

struct LLMInfoView: View {
    var body: some View {
        List {
            Section("概要") {
                Text("このアプリでは、本の表紙や奥付からOCRで読み取ったテキストを、AIを使って解析し、タイトル・著者名・ISBNなどの書籍情報を自動抽出します。")
                    .font(.body)
            }

            Section("Apple Intelligence") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("iOS 26以降で利用可能なAppleのオンデバイスAIです。")
                    Text("• 追加のダウンロード不要")
                    Text("• システムに最適化された高速処理")
                    Text("• プライバシー保護（データは端末外に送信されません）")
                }
                .font(.body)
            }

            Section("ローカルモデル (Gemma 2B)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Googleが開発した軽量で高性能な言語モデルです。")
                    Text("• iOS 17以降で動作")
                    Text("• オフラインで動作")
                    Text("• 約\(LlamaService.ModelInfo.displayFileSize)のダウンロードが必要")
                    Text("• 日本語・英語に対応")
                }
                .font(.body)
            }

            Section("プライバシー") {
                Text("すべてのAI処理は端末内で完結します。画像やテキストがインターネットに送信されることはありません。")
                    .font(.body)
            }
        }
        .navigationTitle("LLMについて")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LLMSettingsView()
    }
}
