//
//  ExtractedTextsView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct ExtractedTextsView: View {
    @StateObject private var viewModel = DependencyContainer.shared.makeExtractedTextsViewModel()
    @State private var selectedItem: ExtractedTextItem?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.items.isEmpty {
                    emptyStateView
                } else {
                    tableListView
                }
            }
            .navigationTitle("書誌情報")
            .task {
                await viewModel.loadItems()
            }
            .refreshable {
                await viewModel.loadItems()
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
            .sheet(item: $selectedItem) { item in
                bookDetailSheet(item: item)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("書誌情報がありません")
                .font(.headline)
            Text("詳細画面で「抽出」ボタンを押すと\nOCRでテキストを抽出し、\n書誌情報を取得できます")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var tableListView: some View {
        List {
            ForEach(viewModel.groupedItems) { group in
                Section {
                    ForEach(group.items) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    // Book title
                                    Text(item.bookTitle ?? item.displayTitle)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)

                                    // Author
                                    if let author = item.bookAuthor {
                                        Text(author)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                // Chevron indicator
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(group.category)
                        Spacer()
                        Text("\(group.items.count)件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func bookDetailSheet(item: ExtractedTextItem) -> some View {
        NavigationStack {
            List {
                // Thumbnail section
                if let path = item.thumbnailPath,
                   let image = FileStorageManager.shared.loadThumbnail(fileName: path) {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // Book info section
                Section("書誌情報") {
                    if let title = item.bookTitle {
                        infoRow("タイトル", value: title)
                    }
                    if let author = item.bookAuthor {
                        infoRow("著者", value: author)
                    }
                    if let publisher = item.bookPublisher {
                        infoRow("出版社", value: publisher)
                    }
                    if let isbn = item.bookISBN, !isbn.isEmpty {
                        infoRow("ISBN", value: isbn)
                    }
                    if let category = item.bookCategory {
                        infoRow("カテゴリ", value: category)
                    }
                    if let processedAt = item.ocrProcessedAt {
                        infoRow("取得日時", value: formatDate(processedAt))
                    }
                }

                // Extracted text section
                if let text = item.extractedText, !text.isEmpty {
                    Section {
                        DisclosureGroup("抽出テキスト") {
                            Text(text)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        selectedItem = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
