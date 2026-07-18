import SwiftUI
import AppKit

enum CoverCheckTheme {
    static let backgroundTop = Color(red: 0.07, green: 0.09, blue: 0.12)
    static let backgroundBottom = Color(red: 0.11, green: 0.14, blue: 0.18)
    static let panel = Color(red: 0.14, green: 0.17, blue: 0.22).opacity(0.92)
    static let panelStroke = Color.white.opacity(0.08)
    static let textPrimary = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let textSecondary = Color(red: 0.68, green: 0.73, blue: 0.78)
    static let accent = Color(red: 0.95, green: 0.72, blue: 0.28)
    static let accentDeep = Color(red: 0.86, green: 0.45, blue: 0.18)
    static let ok = Color(red: 0.35, green: 0.78, blue: 0.55)
    static let warning = Color(red: 0.95, green: 0.72, blue: 0.28)
    static let error = Color(red: 0.93, green: 0.38, blue: 0.34)
    static let neutral = Color(red: 0.62, green: 0.68, blue: 0.74)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom, Color(red: 0.08, green: 0.12, blue: 0.16)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var heroGlow: RadialGradient {
        RadialGradient(
            colors: [accent.opacity(0.22), accentDeep.opacity(0.08), .clear],
            center: .topTrailing,
            startRadius: 20,
            endRadius: 420
        )
    }
}

extension ArtworkStatus {
    var color: Color {
        switch tint {
        case .ok: return CoverCheckTheme.ok
        case .warning: return CoverCheckTheme.warning
        case .error: return CoverCheckTheme.error
        case .neutral: return CoverCheckTheme.neutral
        }
    }
}

struct ArtworkImage: View {
    let data: Data?
    var cornerRadius: CGFloat = 12
    var placeholderSystemImage: String = "music.note"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.04))

            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Image(systemName: placeholderSystemImage)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(CoverCheckTheme.textSecondary.opacity(0.7))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(CoverCheckTheme.panelStroke, lineWidth: 1)
        )
    }
}
