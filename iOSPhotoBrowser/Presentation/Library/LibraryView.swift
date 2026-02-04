//
//  LibraryView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    @State private var showingImportSheet = false

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeLibraryViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.photos.isEmpty {
                    EmptyStateView(
                        icon: "photo.on.rectangle.angled",
                        title: "写真がありません",
                        message: "上部の「＋」ボタンから写真を追加してください"
                    )
                } else {
                    photoGrid
                }
            }
            .navigationTitle("ライブラリ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingImportSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
            }
            .task {
                await viewModel.loadPhotos()
            }
            .refreshable {
                await viewModel.loadPhotos()
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
            .sheet(isPresented: $showingImportSheet) {
                // Reload photos when sheet is dismissed
                Task {
                    await viewModel.loadPhotos()
                }
            } content: {
                ImportView()
            }
        }
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.photos) { photo in
                    NavigationLink(value: photo) {
                        PhotoGridItem(photo: photo)
                    }
                }
            }
            .padding(4)
        }
        .navigationDestination(for: PhotoItem.self) { photo in
            DetailView(photoId: photo.id)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    viewModel.changeSortOption(option)
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if viewModel.sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
}
