import SwiftUI

@main
struct CoverCheckApp: App {
    @StateObject private var scanController = ScanController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanController)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Choose Music Folder…") {
                    scanController.chooseDirectory()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Start Scan") {
                    Task { await scanController.startScan() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(scanController.rootURL == nil || scanController.isScanning)

                Button("Cancel Scan") {
                    scanController.cancelScan()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!scanController.isScanning)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(scanController)
        }
    }
}
