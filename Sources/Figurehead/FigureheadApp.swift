import SwiftUI

@main
struct FigureheadApp: App {
    @State private var model = AppModel()

    init() {
        SelfTest.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 1060, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Capture Window…") { model.beginCapture(.newLayer) }
                    .keyboardShortcut("n")
                Button("Import Window Image…") { model.importImage(to: .newLayer) }
                    .keyboardShortcut("o")
                Divider()
                Button("Open Project…") { model.openProject() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Project") { model.saveProject() }
                    .keyboardShortcut("s")
            }
            CommandMenu("Shot") {
                Button("Render Light + Dark…") { model.exportPNGs() }
                    .keyboardShortcut("e")
                Button("Copy Preview Image") { model.copyPreview() }
                    .keyboardShortcut("c")
                Divider()
                Button(model.previewDark ? "Preview Light Appearance"
                                         : "Preview Dark Appearance") {
                    model.previewDark.toggle()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}
