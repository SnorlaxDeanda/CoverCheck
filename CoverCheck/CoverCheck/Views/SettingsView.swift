import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: ScanController

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

            Section("About") {
                LabeledContent("App", value: "CoverCheck")
                LabeledContent("Purpose", value: "Verify album artwork in a music folder")
                Text("Online lookups use the iTunes Search API and Cover Art Archive when available. No API key is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
        .padding()
    }
}
