import SwiftUI

/// Sheet listing capturable windows, with a permission explainer when
/// Screen Recording access has not been granted.
struct WindowPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var windows: [WindowInfo] = []
    @State private var loading = true
    @State private var hasPermission = WindowCapture.hasPermission

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Capture a Window")
                    .font(.headline)
                Spacer()
                if hasPermission {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh window list")
                }
            }
            .padding(12)

            Divider()

            if !hasPermission {
                permissionExplainer
            } else if loading {
                ProgressView("Finding windows…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if windows.isEmpty {
                VStack(spacing: 8) {
                    Text("No capturable windows found.")
                    Text("Windows must be on screen and larger than a thumbnail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(windows) { info in
                    Button {
                        model.captureWindow(info)
                    } label: {
                        HStack {
                            Image(systemName: "macwindow")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(info.app).fontWeight(.medium)
                                if !info.title.isEmpty {
                                    Text(info.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(Int(info.frame.width)) × \(Int(info.frame.height))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text("The picker sheet closes first, then the shot is taken.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(width: 480, height: 420)
        .task { await refresh() }
    }

    private var permissionExplainer: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.badge.record")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.orange)
            Text("Screen Recording access needed")
                .font(.title3.weight(.semibold))
            Text("Figurehead uses ScreenCaptureKit to take crisp, shadow-free screenshots of a single window. macOS gates that behind the Screen Recording permission.\n\nGrant it in System Settings → Privacy & Security → Screen Recording, then relaunch Figurehead — macOS applies the grant on the next launch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack {
                Button("Request Access") {
                    WindowCapture.requestPermission()
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        hasPermission = WindowCapture.hasPermission
                        if hasPermission { await refresh() }
                    }
                }
                Button("Open System Settings") {
                    WindowCapture.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func refresh() async {
        hasPermission = WindowCapture.hasPermission
        guard hasPermission else { return }
        loading = true
        windows = await WindowCapture.listWindows()
        loading = false
    }
}
