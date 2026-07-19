import AppKit

/// Headless smoke test: `swift run Figurehead --selftest` renders a sample
/// two-layer project (synthetic window bitmaps, caption, grain) in light and
/// dark at 1x and 2x, writes PNGs to a temp folder, and exits non-zero on any
/// failure. No UI, no Screen Recording permission needed.
@MainActor
enum SelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        exit(run() ? 0 : 1)
    }

    private static func run() -> Bool {
        var project = Project()
        project.canvas = CanvasSpec(width: 1200, height: 630)
        project.backdrop.grain = true
        project.caption.text = "Selftest Headline"
        project.layers = [ShotLayer(name: "back"), ShotLayer(name: "front")]

        guard let fakeWindow = syntheticWindow(width: 800, height: 520) else {
            print("selftest: FAILED to build synthetic window")
            return false
        }

        // Apply the duo arrangement placements directly.
        let duo = Arrangement.duo.placements
        for i in 0..<2 {
            let (s, ox, oy, r) = duo[i]
            project.layers[i].scale = s
            project.layers[i].offsetX = ox
            project.layers[i].offsetY = oy
            project.layers[i].rotation = r
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("figurehead-selftest-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for dark in [false, true] {
            for factor in [1, 2] {
                guard let img = Compositor.render(project: project, dark: dark,
                                                  scale: CGFloat(factor),
                                                  imageProvider: { _ in fakeWindow })
                else {
                    print("selftest: FAILED render dark=\(dark) scale=\(factor)")
                    return false
                }
                let expectedW = project.canvas.width * factor
                guard img.width == expectedW else {
                    print("selftest: FAILED size \(img.width) != \(expectedW)")
                    return false
                }
                let url = dir.appendingPathComponent("shot-\(dark ? "dark" : "light")\(factor == 2 ? "@2x" : "").png")
                do { try AppModel.writePNG(img, to: url) } catch {
                    print("selftest: FAILED writing \(url.lastPathComponent): \(error)")
                    return false
                }
            }
        }
        print("selftest: OK — 4 renders written to \(dir.path)")
        return true
    }

    /// A fake "window": rounded rect with a titlebar band, so corner
    /// transparency and shadow shaping get exercised.
    private static func syntheticWindow(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 20, cornerHeight: 20,
                           transform: nil))
        ctx.clip()
        ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        ctx.fill(rect)
        ctx.setFillColor(CGColor(srgbRed: 0.88, green: 0.89, blue: 0.91, alpha: 1))
        ctx.fill(CGRect(x: 0, y: rect.maxY - 56, width: rect.width, height: 56))
        return ctx.makeImage()
    }
}
