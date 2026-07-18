import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject private var controller: ScanController
    let album: AlbumVerification
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                artworkComparison
                messagesSection
                tracksSection
            }
            .padding(28)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .background(Color.clear)
        .onAppear {
            appeared = false
            withAnimation(.easeOut(duration: 0.28)) {
                appeared = true
            }
        }
        .onChange(of: album.id) { _, _ in
            appeared = false
            withAnimation(.easeOut(duration: 0.28)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(album.album)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(CoverCheckTheme.textPrimary)

                Text(album.artist)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CoverCheckTheme.textSecondary)

                HStack(spacing: 10) {
                    StatusBadge(status: album.status)

                    Text("\(album.trackCount) tracks")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CoverCheckTheme.textSecondary)

                    if let score = album.similarityScore {
                        Text(String(format: "%.0f%% match to reference", score * 100))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(CoverCheckTheme.textSecondary)
                    }
                }
                .padding(.top, 4)
            }

            Spacer()

            if let track = album.tracks.first {
                Button {
                    controller.revealInFinder(track.url.deletingLastPathComponent())
                } label: {
                    Label("Show in Finder", systemImage: "finder")
                }
                .buttonStyle(GlowButtonStyle())
            }
        }
    }

    private var artworkComparison: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Artwork comparison")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CoverCheckTheme.textPrimary)

            HStack(alignment: .top, spacing: 20) {
                ArtworkColumn(title: "Embedded", data: album.embeddedArtworkData)
                ArtworkColumn(title: "Folder", data: album.folderArtworkData, placeholder: "folder")
                ArtworkColumn(
                    title: album.referenceSource.map { "Reference · \($0)" } ?? "Reference",
                    data: album.referenceArtworkData,
                    placeholder: "globe"
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CoverCheckTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CoverCheckTheme.panelStroke, lineWidth: 1)
        )
    }

    private var messagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Findings")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CoverCheckTheme.textPrimary)

            ForEach(Array(album.messages.enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(album.status.color)
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    Text(message)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(CoverCheckTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracks")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CoverCheckTheme.textPrimary)

            VStack(spacing: 0) {
                ForEach(album.tracks) { track in
                    HStack(spacing: 12) {
                        Text(track.trackNumber.map(String.init) ?? "–")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CoverCheckTheme.textSecondary)
                            .frame(width: 28, alignment: .trailing)

                        ArtworkImage(data: track.artworkData, cornerRadius: 6)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(CoverCheckTheme.textPrimary)
                                .lineLimit(1)
                            Text(track.fileName)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(CoverCheckTheme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: track.hasEmbeddedArtwork ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(track.hasEmbeddedArtwork ? CoverCheckTheme.ok : CoverCheckTheme.error)

                        Button {
                            controller.revealInFinder(track.url)
                        } label: {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(CoverCheckTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    if track.id != album.tracks.last?.id {
                        Divider().overlay(CoverCheckTheme.panelStroke)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CoverCheckTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CoverCheckTheme.panelStroke, lineWidth: 1)
            )
        }
    }
}

struct ArtworkColumn: View {
    let title: String
    let data: Data?
    var placeholder: String = "music.note"

    var body: some View {
        VStack(spacing: 10) {
            ArtworkImage(data: data, cornerRadius: 14, placeholderSystemImage: placeholder)
                .frame(width: 160, height: 160)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CoverCheckTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 160)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatusBadge: View {
    let status: ArtworkStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.systemImage)
            Text(status.rawValue)
                .fontWeight(.semibold)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(status.color)
        .background(status.color.opacity(0.14))
        .clipShape(Capsule())
    }
}
