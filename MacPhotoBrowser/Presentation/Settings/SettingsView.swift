//
//  SettingsView.swift
//  MacPhotoBrowser
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: - AI処理
                Section {
                    NavigationLink {
                        LLMSettingsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("AI処理")
                                Text("書籍情報の自動抽出")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "brain")
                        }
                    }
                } header: {
                    Text("機能設定")
                }

                // MARK: - アプリ情報
                Section {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("ビルド")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("アプリ情報")
                }
            }
            .navigationTitle("設定")
                        .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
