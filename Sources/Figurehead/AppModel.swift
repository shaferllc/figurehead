import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ImageKey: Hashable, Sendable {
    let layer: UUID
    let dark: Bool
}

@MainActor @Observable
final class AppModel {

    var project = Project()
    /// Runtime bitmap cache. Persisted as PNGs in the project bundle on save.
    var images: [ImageKey: CGImage] = [:]
    var selectedLayerID: UUID?
    var previewDark = false
    var projectURL: URL?
    var status = "Capture a window to get started."
    var showingPicker = false
    var pickerTarget: PickerTarget = .newLayer

    enum PickerTarget {
        case newLayer
        case lightSlot(UUID)
        case darkSlot(UUID)
    }

    // MARK: - Image resolution

    /// Layer image for an appearance; dark falls back to the light capture.
    func image(for layer: ShotLayer, dark: Bool) -> CGImage? {
        if dark, let d = images[ImageKey(layer: layer.id, dark: true)] { return d }
        return images[ImageKey(layer: layer.id, dark: false)]
    }

    func hasDarkImage(_ layer: ShotLayer) -> Bool {
        images[ImageKey(layer: layer.id, dark: true)] != nil
    }

    var selectedLayerIndex: Int? {
        guard let id = selectedLayerID else { return nil }
        return project.layers.firstIndex { $0.id == id }
    }

    // MARK: - Capture

    func beginCapture(_ target: PickerTarget) {
        pickerTarget = target
        showingPicker = true
    }

    /// Called from the window picker. Waits a beat so the sheet is gone
    /// before the screenshot is taken.
    func captureWindow(_ info: WindowInfo) {
        showingPicker = false
        let target = pickerTarget
        status = "Capturing \(info.app)…"
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard let img = await WindowCapture.capture(windowID: info.id) else {
                status = "Capture failed — is Screen Recording access granted?"
                return
            }
            apply(img, windowID: info.id, name: windowName(info), to: target)
        }
    }

    func recapture(layerID: UUID, dark: Bool) {
        guard let idx = project.layers.firstIndex(where: { $0.id == layerID }) else { return }
        let layer = project.layers[idx]
        guard let windowID = dark ? layer.darkSourceWindowID : layer.sourceWindowID else { return }
        status = "Recapturing \(layer.name)…"
        Task {
            guard let img = await WindowCapture.capture(windowID: CGWindowID(windowID)) else {
                status = "Recapture failed — that window may be gone. Pick it again."
                return
            }
            images[ImageKey(layer: layerID, dark: dark)] = img
            status = "Recaptured \(layer.name) (\(dark ? "dark" : "light"))."
        }
    }

    private func windowName(_ info: WindowInfo) -> String {
        info.title.isEmpty ? info.app : "\(info.app) — \(info.title)"
    }

    private func apply(_ img: CGImage, windowID: CGWindowID?, name: String,
                       to target: PickerTarget) {
        switch target {
        case .newLayer:
            guard project.layers.count < 6 else {
                status = "Layer limit reached."
                return
            }
            var layer = ShotLayer(name: name)
            layer.sourceWindowID = windowID
            project.layers.append(layer)
            images[ImageKey(layer: layer.id, dark: false)] = img
            selectedLayerID = layer.id
            status = "Added \(name)."
        case .lightSlot(let id):
            guard let idx = project.layers.firstIndex(where: { $0.id == id }) else { return }
            images[ImageKey(layer: id, dark: false)] = img
            project.layers[idx].sourceWindowID = windowID
            status = "Replaced light capture for \(project.layers[idx].name)."
        case .darkSlot(let id):
            guard let idx = project.layers.firstIndex(where: { $0.id == id }) else { return }
            images[ImageKey(layer: id, dark: true)] = img
            project.layers[idx].darkSourceWindowID = windowID
            status = "Set dark capture for \(project.layers[idx].name)."
        }
    }

    // MARK: - Import

    func importImage(to target: PickerTarget) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.message = "Choose a window screenshot (PNG recommended)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importImage(from: url, to: target)
    }

    func importImage(from url: URL, to target: PickerTarget) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            status = "Could not read \(url.lastPathComponent)."
            return
        }
        apply(img, windowID: nil, name: url.deletingPathExtension().lastPathComponent,
              to: target)
    }

    // MARK: - Layers

    func removeLayer(_ id: UUID) {
        project.layers.removeAll { $0.id == id }
        images[ImageKey(layer: id, dark: false)] = nil
        images[ImageKey(layer: id, dark: true)] = nil
        if selectedLayerID == id { selectedLayerID = project.layers.last?.id }
    }

    func clearDarkImage(_ id: UUID) {
        images[ImageKey(layer: id, dark: true)] = nil
        if let idx = project.layers.firstIndex(where: { $0.id == id }) {
            project.layers[idx].darkSourceWindowID = nil
            project.layers[idx].darkFile = nil
        }
    }

    func applyArrangement(_ arrangement: Arrangement) {
        let placements = arrangement.placements
        let n = min(placements.count, project.layers.count)
        guard n > 0 else {
            status = "Add a capture first."
            return
        }
        for i in 0..<n {
            let (scale, ox, oy, rot) = placements[i]
            project.layers[i].scale = scale
            project.layers[i].offsetX = ox
            project.layers[i].offsetY = oy
            project.layers[i].rotation = rot
        }
        status = "Applied \(arrangement.label) arrangement to \(n) layer\(n == 1 ? "" : "s")."
    }

    // MARK: - Rendering

    func renderImage(dark: Bool, scale: CGFloat) -> CGImage? {
        Compositor.render(project: project, dark: dark, scale: scale) { layer in
            image(for: layer, dark: dark)
        }
    }

    /// Preview at a bounded pixel size so slider scrubbing stays fluid.
    func renderPreview() -> NSImage? {
        let scale = min(1, 1600 / CGFloat(max(project.canvas.width, 1)))
        guard let cg = renderImage(dark: previewDark, scale: scale) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: - Export

    func exportPNGs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the rendered PNGs (light + dark, 1x + 2x)."
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var written: [String] = []
        for dark in [false, true] {
            for factor in [1, 2] {
                guard let img = renderImage(dark: dark, scale: CGFloat(factor)) else { continue }
                let name = "shot-\(dark ? "dark" : "light")\(factor == 2 ? "@2x" : "").png"
                do {
                    try Self.writePNG(img, to: folder.appendingPathComponent(name))
                    written.append(name)
                } catch {
                    status = "Export failed on \(name): \(error.localizedDescription)"
                    return
                }
            }
        }
        status = written.isEmpty
            ? "Nothing to export yet."
            : "Exported \(written.count) files to \(folder.lastPathComponent)/."
    }

    func copyPreview() {
        guard let cg = renderImage(dark: previewDark, scale: 1) else {
            status = "Nothing to copy yet."
            return
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        status = "Copied \(previewDark ? "dark" : "light") render (\(cg.width) × \(cg.height))."
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                         UTType.png.identifier as CFString,
                                                         1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    // MARK: - Project save / load

    func saveProject() {
        let url: URL
        if let projectURL {
            url = projectURL
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Untitled.figurehead"
            panel.canCreateDirectories = true
            panel.message = "A Figurehead project is a folder: project.json + captured PNGs."
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }
        do {
            try writeProject(to: url)
            projectURL = url
            status = "Saved \(url.lastPathComponent)."
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    private func writeProject(to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        for idx in project.layers.indices {
            let layer = project.layers[idx]
            if let img = images[ImageKey(layer: layer.id, dark: false)] {
                let name = "layer-\(layer.id.uuidString)-light.png"
                try Self.writePNG(img, to: url.appendingPathComponent(name))
                project.layers[idx].lightFile = name
            }
            if let img = images[ImageKey(layer: layer.id, dark: true)] {
                let name = "layer-\(layer.id.uuidString)-dark.png"
                try Self.writePNG(img, to: url.appendingPathComponent(name))
                project.layers[idx].darkFile = name
            } else {
                project.layers[idx].darkFile = nil
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: url.appendingPathComponent("project.json"), options: .atomic)
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json, .folder]
        panel.message = "Choose a .figurehead project folder (or its project.json)."
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let dir = chosen.lastPathComponent == "project.json"
            ? chosen.deletingLastPathComponent() : chosen
        do {
            try loadProject(from: dir)
            projectURL = dir
            status = "Opened \(dir.lastPathComponent)."
        } catch {
            status = "Open failed: \(error.localizedDescription)"
        }
    }

    private func loadProject(from dir: URL) throws {
        let data = try Data(contentsOf: dir.appendingPathComponent("project.json"))
        let loaded = try JSONDecoder().decode(Project.self, from: data)
        var cache: [ImageKey: CGImage] = [:]
        for layer in loaded.layers {
            if let f = layer.lightFile, let img = Self.readPNG(dir.appendingPathComponent(f)) {
                cache[ImageKey(layer: layer.id, dark: false)] = img
            }
            if let f = layer.darkFile, let img = Self.readPNG(dir.appendingPathComponent(f)) {
                cache[ImageKey(layer: layer.id, dark: true)] = img
            }
        }
        project = loaded
        images = cache
        selectedLayerID = loaded.layers.last?.id
    }

    private static func readPNG(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
