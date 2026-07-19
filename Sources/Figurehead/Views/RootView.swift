import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HSplitView {
            LayerPanel()
                .frame(minWidth: 210, idealWidth: 235, maxWidth: 300)
            PreviewPane()
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            InspectorView()
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.beginCapture(.newLayer)
                } label: {
                    Label("Capture Window", systemImage: "camera.viewfinder")
                }
                .help("Capture an on-screen window (⌘N)")

                Button {
                    model.importImage(to: .newLayer)
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import an existing window screenshot (⌘O)")
            }
            ToolbarItemGroup {
                Picker("Appearance", selection: $model.previewDark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Preview appearance — export always renders both")
            }
            ToolbarItemGroup {
                Button {
                    model.copyPreview()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy the current preview as an image (⌘C)")

                Button {
                    model.exportPNGs()
                } label: {
                    Label("Render Light + Dark", systemImage: "square.and.arrow.up.on.square")
                }
                .help("Export light + dark PNGs at 1x and 2x (⌘E)")
            }
        }
        .sheet(isPresented: $model.showingPicker) {
            WindowPickerView()
        }
        .navigationTitle(model.projectURL.map {
            $0.deletingPathExtension().lastPathComponent
        } ?? "Figurehead")
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
    }

    private var statusBar: some View {
        HStack {
            Text(model.status)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("\(model.project.canvas.width) × \(model.project.canvas.height) px · \(model.previewDark ? "Dark" : "Light")")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

// MARK: - Preview pane

struct PreviewPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let preview = model.renderPreview() {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .padding(18)
            } else {
                emptyState
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let ok = urls.filter { ["png", "jpg", "jpeg", "tiff"].contains($0.pathExtension.lowercased()) }
            for url in ok { model.importImage(from: url, to: .newLayer) }
            return !ok.isEmpty
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing staged yet")
                .font(.title3.weight(.semibold))
            Text("Capture an app window, import a screenshot,\nor drop a PNG here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Capture Window…") { model.beginCapture(.newLayer) }
                    .keyboardShortcut(.defaultAction)
                Button("Import…") { model.importImage(to: .newLayer) }
            }
        }
        .padding(40)
    }
}

// MARK: - Layer panel

struct LayerPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $model.selectedLayerID) {
                Section("Layers (back → front)") {
                    ForEach(model.project.layers) { layer in
                        LayerRow(layer: layer)
                            .tag(layer.id)
                    }
                    .onMove { from, to in
                        model.project.layers.move(fromOffsets: from, toOffset: to)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Arrange")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Arrangement.allCases) { arr in
                        Button(arr.label) { model.applyArrangement(arr) }
                            .disabled(model.project.layers.isEmpty)
                            .help("Position the first \(arr.layerCount) layer\(arr.layerCount == 1 ? "" : "s")")
                    }
                }
                .controlSize(.small)
            }
            .padding(10)
        }
    }
}

struct LayerRow: View {
    @Environment(AppModel.self) private var model
    let layer: ShotLayer

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "macwindow")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.hasDarkImage(layer) {
                    Text("light + dark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if layer.sourceWindowID != nil {
                Button {
                    model.recapture(layerID: layer.id, dark: false)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Recapture this window")
            }
        }
        .contextMenu {
            Button("Remove Layer", role: .destructive) { model.removeLayer(layer.id) }
        }
    }
}
