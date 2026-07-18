import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: ScanController

    var body: some View {
        ZStack {
            CoverCheckTheme.backgroundGradient.ignoresSafeArea()
            CoverCheckTheme.heroGlow.ignoresSafeArea()

            if controller.albums.isEmpty && !controller.isScanning && controller.phase != .finished {
                WelcomeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ResultsWorkspace()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: controller.albums.isEmpty)
        .preferredColorScheme(.dark)
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var controller: ScanController
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(CoverCheckTheme.accent.opacity(pulse ? 0.18 : 0.08))
                        .frame(width: 148, height: 148)
                        .scaleEffect(pulse ? 1.08 : 0.96)

                    Circle()
                        .stroke(CoverCheckTheme.accent.opacity(0.35), lineWidth: 1)
                        .frame(width: 118, height: 118)

                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(CoverCheckTheme.accent)
                        .symbolEffect(.pulse, options: .repeating, value: pulse)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

                VStack(spacing: 10) {
                    Text("CoverCheck")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(CoverCheckTheme.textPrimary)

                    Text("Scan a music library and verify that every album’s artwork is present, consistent, and correct.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(CoverCheckTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                VStack(spacing: 14) {
                    Button {
                        controller.chooseDirectory()
                    } label: {
                        Label(
                            controller.rootURL == nil ? "Choose Music Folder" : "Change Folder",
                            systemImage: "folder.badge.plus"
                        )
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(minWidth: 220)
                    }
                    .buttonStyle(GlowButtonStyle())

                    if let rootURL = controller.rootURL {
                        Text(rootURL.path)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(CoverCheckTheme.textSecondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: 560)

                        Button {
                            Task { await controller.startScan() }
                        } label: {
                            Label(
                                controller.isScanning ? "Scanning…" : "Start Scan",
                                systemImage: "play.fill"
                            )
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(minWidth: 220)
                        }
                        .buttonStyle(GlowButtonStyle(filled: true))
                        .disabled(controller.isScanning)
                    }
                }

                if controller.isScanning || controller.phase.progress != nil {
                    ScanProgressBanner()
                        .frame(maxWidth: 560)
                        .padding(.top, 8)
                }

                HStack(spacing: 22) {
                    FeatureChip(icon: "photo", title: "Embedded art")
                    FeatureChip(icon: "folder", title: "Folder covers")
                    FeatureChip(icon: "globe", title: "Online reference")
                }
                .padding(.top, 18)
            }
            .padding(40)

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureChip: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(CoverCheckTheme.accent)
            Text(title)
                .foregroundStyle(CoverCheckTheme.textSecondary)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
    }
}

struct GlowButtonStyle: ButtonStyle {
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: filled
                                ? [CoverCheckTheme.accent, CoverCheckTheme.accentDeep]
                                : [CoverCheckTheme.panel, CoverCheckTheme.panel],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CoverCheckTheme.panelStroke, lineWidth: 1)
            )
            .foregroundStyle(filled ? Color.black.opacity(0.85) : CoverCheckTheme.textPrimary)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ScanProgressBanner: View {
    @EnvironmentObject private var controller: ScanController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(controller.phase.label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CoverCheckTheme.textPrimary)
                Spacer()
                if controller.isScanning {
                    Button("Cancel") {
                        controller.cancelScan()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CoverCheckTheme.accent)
                }
            }

            ProgressView(value: controller.phase.progress)
                .progressViewStyle(.linear)
                .tint(CoverCheckTheme.accent)
        }
        .padding(16)
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
