import SwiftUI

struct ResultsWorkspace: View {
    @EnvironmentObject private var controller: ScanController

    var body: some View {
        VStack(spacing: 0) {
            ToolbarHeader()

            if controller.isScanning {
                ScanProgressBanner()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            HStack(spacing: 0) {
                AlbumListPane()
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)

                Divider().overlay(CoverCheckTheme.panelStroke)

                if let album = controller.selectedAlbum {
                    AlbumDetailView(album: album)
                } else {
                    emptyDetail
                }
            }
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CoverCheckTheme.textSecondary)
            Text("Select an album to inspect artwork")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(CoverCheckTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToolbarHeader: View {
    @EnvironmentObject private var controller: ScanController

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CoverCheck")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(CoverCheckTheme.textPrimary)

                Text(controller.rootURL?.path ?? "No folder selected")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CoverCheckTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HStack(spacing: 18) {
                StatPill(title: "Albums", value: "\(controller.albums.count)")
                StatPill(title: "Tracks", value: "\(controller.trackCount)")
                StatPill(title: "Issues", value: "\(controller.issueCount)", emphasize: controller.issueCount > 0)
            }

            Button {
                controller.chooseDirectory()
            } label: {
                Label("Folder", systemImage: "folder")
            }
            .buttonStyle(GlowButtonStyle())

            Button {
                Task { await controller.startScan() }
            } label: {
                Label(controller.isScanning ? "Scanning" : "Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GlowButtonStyle(filled: true))
            .disabled(controller.rootURL == nil || controller.isScanning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

struct StatPill: View {
    let title: String
    let value: String
    var emphasize: Bool = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(CoverCheckTheme.textSecondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(emphasize ? CoverCheckTheme.error : CoverCheckTheme.textPrimary)
        }
    }
}

struct AlbumListPane: View {
    @EnvironmentObject private var controller: ScanController

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(CoverCheckTheme.textSecondary)
                    TextField("Search albums or artists", text: $controller.searchText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(CoverCheckTheme.textPrimary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )

                Picker("Filter", selection: $controller.statusFilter) {
                    ForEach(StatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(14)

            List(selection: $controller.selectedAlbumID) {
                ForEach(controller.filteredAlbums) { album in
                    AlbumRow(album: album)
                        .tag(album.id)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(CoverCheckTheme.panel.opacity(0.55))
    }
}

struct AlbumRow: View {
    let album: AlbumVerification

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(data: album.embeddedArtworkData, cornerRadius: 8)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(album.album)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CoverCheckTheme.textPrimary)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CoverCheckTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: album.status.systemImage)
                    .foregroundStyle(album.status.color)
                Text("\(album.trackCount)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(CoverCheckTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
