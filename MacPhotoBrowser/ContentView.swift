//
//  ContentView.swift
//  MacPhotoBrowser
//

import SwiftUI

enum SidebarItem: Hashable {
    case library
    case search
    case album(Album)
    case tag(Tag)
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .library
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var albumsViewModel = DependencyContainer.shared.makeAlbumsViewModel()
    @StateObject private var tagsViewModel = DependencyContainer.shared.makeTagsViewModel()
    @State private var dropTargetAlbumId: UUID?
    @State private var dropTargetTagId: UUID?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("サイドバーの表示/非表示 (⌘⌃S)")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
        .task {
            await albumsViewModel.loadAlbums()
            await tagsViewModel.loadTags()
        }
    }

    private func toggleSidebar() {
        withAnimation {
            if columnVisibility == .detailOnly {
                columnVisibility = .all
            } else {
                columnVisibility = .detailOnly
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedItem) {
            Section {
                Label("ライブラリ", systemImage: "photo.on.rectangle.angled")
                    .tag(SidebarItem.library)

                Label("検索", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
            }

            Section(isExpanded: .constant(true)) {
                ForEach(albumsViewModel.albums) { album in
                    Label(album.name, systemImage: "rectangle.stack.fill")
                        .badge(albumsViewModel.albumImageCounts[album.id] ?? 0)
                        .tag(SidebarItem.album(album))
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(dropTargetAlbumId == album.id ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .dropDestination(for: String.self) { items, _ in
                            guard let uuidString = items.first,
                                  let photoId = UUID(uuidString: uuidString) else { return false }
                            Task {
                                try? await DependencyContainer.shared.albumRepository.addImage(photoId, to: album.id)
                                await albumsViewModel.loadAlbums()
                            }
                            return true
                        } isTargeted: { isTargeted in
                            dropTargetAlbumId = isTargeted ? album.id : nil
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await albumsViewModel.deleteAlbum(album) }
                            } label: {
                                Label("アルバムを削除", systemImage: "trash")
                            }
                        }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let album = albumsViewModel.albums[index]
                        Task { await albumsViewModel.deleteAlbum(album) }
                    }
                }

                Button {
                    albumsViewModel.showingCreateSheet = true
                } label: {
                    Label("新規アルバム...", systemImage: "plus")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } header: {
                HStack {
                    Text("マイアルバム")
                    Spacer()
                    Button {
                        albumsViewModel.showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section(isExpanded: .constant(true)) {
                ForEach(tagsViewModel.tagsWithCount) { tagWithCount in
                    Label(tagWithCount.tag.name, systemImage: "tag.fill")
                        .badge(tagWithCount.imageCount)
                        .tag(SidebarItem.tag(tagWithCount.tag))
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(dropTargetTagId == tagWithCount.tag.id ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .dropDestination(for: String.self) { items, _ in
                            guard let uuidString = items.first,
                                  let photoId = UUID(uuidString: uuidString) else { return false }
                            Task {
                                try? await DependencyContainer.shared.tagRepository.addTag(tagWithCount.tag, to: photoId)
                                await tagsViewModel.loadTags()
                            }
                            return true
                        } isTargeted: { isTargeted in
                            dropTargetTagId = isTargeted ? tagWithCount.tag.id : nil
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await tagsViewModel.deleteTag(tagWithCount.tag) }
                            } label: {
                                Label("タグを削除", systemImage: "trash")
                            }
                        }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let tag = tagsViewModel.tagsWithCount[index].tag
                        Task { await tagsViewModel.deleteTag(tag) }
                    }
                }
            } header: {
                Text("タグ")
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .sheet(isPresented: $albumsViewModel.showingCreateSheet) {
            createAlbumSheet
        }
        .alert("エラー", isPresented: $albumsViewModel.showingError) {
            Button("OK") {}
        } message: {
            Text(albumsViewModel.error?.localizedDescription ?? "不明なエラー")
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedItem {
        case .library:
            LibraryView()
        case .search:
            SearchView()
        case .album(let album):
            AlbumDetailView(album: album)
                .id(album.id)
        case .tag(let tag):
            TagImagesView(tag: tag)
                .id(tag.id)
        case nil:
            ContentUnavailableView(
                "写真を表示",
                systemImage: "photo.on.rectangle.angled",
                description: Text("サイドバーから項目を選択してください")
            )
        }
    }

    // MARK: - Create Album Sheet

    private var createAlbumSheet: some View {
        VStack(spacing: 16) {
            Text("新規アルバム")
                .font(.headline)

            TextField("アルバム名を入力", text: $albumsViewModel.newAlbumName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            HStack(spacing: 12) {
                Button("キャンセル") {
                    albumsViewModel.showingCreateSheet = false
                    albumsViewModel.newAlbumName = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("作成") {
                    Task {
                        await albumsViewModel.createAlbum()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(albumsViewModel.newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

#Preview {
    ContentView()
}
