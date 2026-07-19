import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CanvasSection(canvas: $model.project.canvas)
                Divider()
                BackdropSection(backdrop: $model.project.backdrop)
                Divider()
                CaptionSection(caption: $model.project.caption)
                Divider()
                if let idx = model.selectedLayerIndex,
                   model.project.layers.indices.contains(idx) {
                    LayerSection(layer: $model.project.layers[idx])
                } else {
                    Text("Select a layer to edit its placement and shadow.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Reusable bits

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var display: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(display(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

// MARK: - Canvas

struct CanvasSection: View {
    @Binding var canvas: CanvasSpec

    private var presetSelection: String {
        CanvasPreset.all.first {
            $0.width == canvas.width && $0.height == canvas.height
        }?.id ?? "custom"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Canvas")
            Picker("Size", selection: Binding(
                get: { presetSelection },
                set: { id in
                    if let p = CanvasPreset.all.first(where: { $0.id == id }) {
                        canvas.width = p.width
                        canvas.height = p.height
                    }
                }
            )) {
                ForEach(CanvasPreset.all) { p in
                    Text(p.name).tag(p.id)
                }
                Text("Custom").tag("custom")
            }
            .labelsHidden()

            HStack(spacing: 6) {
                TextField("W", value: Binding(
                    get: { canvas.width },
                    set: { canvas.width = min(max($0, 320), 8192) }
                ), format: .number.grouping(.never))
                Text("×").foregroundStyle(.secondary)
                TextField("H", value: Binding(
                    get: { canvas.height },
                    set: { canvas.height = min(max($0, 320), 8192) }
                ), format: .number.grouping(.never))
                Text("px").font(.caption).foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
        }
    }
}

// MARK: - Backdrop

struct BackdropSection: View {
    @Binding var backdrop: BackdropSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Backdrop")

            Picker("Kind", selection: $backdrop.kind) {
                ForEach(BackdropKind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch backdrop.kind {
            case .preset:
                presetGrid
            case .custom:
                ColorPicker("Top / start color",
                            selection: rgbaBinding($backdrop.customA),
                            supportsOpacity: false)
                ColorPicker("Bottom / end color",
                            selection: rgbaBinding($backdrop.customB),
                            supportsOpacity: false)
                Text("Dark render auto-derives darker twins of these colors.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .solid:
                ColorPicker("Fill color",
                            selection: rgbaBinding($backdrop.solid),
                            supportsOpacity: false)
            }

            if backdrop.kind != .solid {
                Picker("Shape", selection: $backdrop.shape) {
                    ForEach(GradientShape.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle("Subtle grain", isOn: $backdrop.grain)
                .controlSize(.small)

            LabeledSlider(label: "Padding", value: $backdrop.paddingFraction,
                          range: 0...0.28,
                          display: { "\(Int($0 * 100))%" })
        }
        .controlSize(.small)
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
            ForEach(GradientPreset.all) { preset in
                Button {
                    backdrop.presetID = preset.id
                } label: {
                    VStack(spacing: 3) {
                        LinearGradient(
                            colors: [color(preset.lightA), color(preset.lightB)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(backdrop.presetID == preset.id
                                                  ? Color.accentColor : .clear,
                                                  lineWidth: 2)
                            )
                        Text(preset.name).font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func color(_ c: RGBA) -> Color {
        Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    private func rgbaBinding(_ binding: Binding<RGBA>) -> Binding<Color> {
        Binding(
            get: {
                Color(.sRGB, red: binding.wrappedValue.r, green: binding.wrappedValue.g,
                      blue: binding.wrappedValue.b, opacity: 1)
            },
            set: { newColor in
                let ns = NSColor(newColor)
                guard let srgb = ns.usingColorSpace(.sRGB) else { return }
                binding.wrappedValue = RGBA(Double(srgb.redComponent),
                                            Double(srgb.greenComponent),
                                            Double(srgb.blueComponent))
            }
        )
    }
}

// MARK: - Caption

struct CaptionSection: View {
    @Binding var caption: CaptionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Caption")
            TextField("Headline (optional)", text: $caption.text)
                .textFieldStyle(.roundedBorder)
            HStack {
                Picker("Weight", selection: $caption.weight) {
                    ForEach(CaptionWeight.allCases) { w in
                        Text(w.label).tag(w)
                    }
                }
                .labelsHidden()
                Picker("Placement", selection: $caption.placement) {
                    ForEach(CaptionPlacement.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .labelsHidden()
            }
            LabeledSlider(label: "Size", value: $caption.sizeFraction,
                          range: 0.02...0.10,
                          display: { String(format: "%.1f%%", $0 * 100) })
            Text("Color is automatic: dark ink on light backdrops, light ink on dark — it flips in the dark render.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
    }
}

// MARK: - Layer

struct LayerSection: View {
    @Environment(AppModel.self) private var model
    @Binding var layer: ShotLayer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Layer")
            TextField("Name", text: $layer.name)
                .textFieldStyle(.roundedBorder)

            LabeledSlider(label: "Scale", value: $layer.scale, range: 0.3...1.6,
                          display: { String(format: "%.0f%%", $0 * 100) })
            LabeledSlider(label: "Offset X", value: $layer.offsetX, range: -0.4...0.4,
                          display: { String(format: "%+.0f%%", $0 * 100) })
            LabeledSlider(label: "Offset Y", value: $layer.offsetY, range: -0.4...0.4,
                          display: { String(format: "%+.0f%%", $0 * 100) })
            LabeledSlider(label: "Rotation", value: $layer.rotation, range: -6...6,
                          display: { String(format: "%+.1f°", $0) })
            LabeledSlider(label: "Corner radius", value: $layer.cornerRadius, range: 0...60,
                          display: { String(format: "%.0f px", $0) })

            SectionHeader("Shadow")
            LabeledSlider(label: "Radius", value: $layer.shadowRadius, range: 0...120,
                          display: { String(format: "%.0f px", $0) })
            LabeledSlider(label: "Opacity", value: $layer.shadowOpacity, range: 0...1,
                          display: { String(format: "%.0f%%", $0 * 100) })
            LabeledSlider(label: "Y offset", value: $layer.shadowOffsetY, range: 0...80,
                          display: { String(format: "%.0f px", $0) })

            SectionHeader("Dark Variant")
            if model.hasDarkImage(layer) {
                HStack {
                    Label("Dark capture set", systemImage: "moon.fill")
                        .font(.caption)
                    Spacer()
                    if layer.darkSourceWindowID != nil {
                        Button("Recapture") {
                            model.recapture(layerID: layer.id, dark: true)
                        }
                    }
                    Button("Remove") { model.clearDarkImage(layer.id) }
                }
            } else {
                Text("Optional: capture the same window with the app switched to dark mode. Dark renders fall back to the light capture without it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Capture Dark…") { model.beginCapture(.darkSlot(layer.id)) }
                    Button("Import Dark…") { model.importImage(to: .darkSlot(layer.id)) }
                }
            }

            Divider()
            HStack {
                Button("Replace Capture…") { model.beginCapture(.lightSlot(layer.id)) }
                Spacer()
                Button("Remove Layer", role: .destructive) {
                    model.removeLayer(layer.id)
                }
            }
        }
        .controlSize(.small)
    }
}
