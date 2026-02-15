//
//  LibraryView.swift
//  MacPhotoBrowser
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    @State private var showingImportSheet = false
    @State private var showingSettings = false
    @State private var selectedPhotoId: UUID?
    @State private var navigationPath = NavigationPath()

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeLibraryViewModel())
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingImportSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("写真を追加")
                }
                ToolbarItem(placement: .automatic) {
                    sortMenu
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("設定")
                }
            }
            .navigationDestination(for: PhotoItem.self) { photo in
                DetailView(photoId: photo.id)
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
            Task {
                await viewModel.loadPhotos()
            }
        } content: {
            ImportView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.photos) { photo in
                    PhotoGridItem(photo: photo, isSelected: selectedPhotoId == photo.id)
                        .onTapGesture(count: 2) {
                            navigationPath.append(photo)
                        }
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded {
                                selectedPhotoId = photo.id
                            }
                        )
                }
            }
            .padding(4)
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
