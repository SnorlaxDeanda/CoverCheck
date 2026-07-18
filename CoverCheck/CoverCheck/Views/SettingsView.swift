import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: ScanController
    @State private var didClearApprovals = false

    var body: some View {
        Form {
            Section("Verification") {
                Toggle("Compare with online reference covers", isOn: $controller.options.compareWithOnlineReference)
                Toggle("Compare with folder artwork (cover.jpg, etc.)", isOn: $controller.options.compareWithFolderArt)

                HStack {
                    Text("Similarity threshold")
                    Spacer()
                    Text("\(Int(controller.options.similarityThreshold * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $controller.options.similarityThreshold, in: 0.70...0.98, step: 0.01)

                Stepper(
                    "Minimum artwork size: \(controller.options.minimumArtworkDimension)px",
                    value: $controller.options.minimumArtworkDimension,
                    in: 200...3000,
                    step: 50
                )
            }

            Section("Approvals") {
                Text("Albums you mark as correct are remembered so CoverCheck won’t keep flagging them, as long as the embedded artwork doesn’t change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Clear All Approvals", role: .destructive) {
                    controller.clearAllApprovals()
                    didClearApprovals = true
                }

                if didClearApprovals {
                    Text("All saved approvals were cleared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("App", value: "CoverCheck")
                LabeledContent("Purpose", value: "Verify and update album artwork in a music folder")
                Text("Online lookups use the iTunes Search API and Cover Art Archive when available. No API key is required. Embedding supports MP3 and M4A/MP4; other formats still get an updated folder cover.jpg.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
        .padding()
    }
}
