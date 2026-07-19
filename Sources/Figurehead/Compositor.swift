import AppKit

/// The one true render. Preview, clipboard, and file export all call
/// `render` — what you see is exactly what ships.
@MainActor
enum Compositor {

    /// Deterministic 128×128 grayscale noise tile for the grain overlay.
    static let noiseTile: CGImage? = {
        let n = 128
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        var px = [UInt8](repeating: 0, count: n * n)
        for i in 0..<px.count {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            px[i] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        return px.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n,
                                      bitsPerComponent: 8, bytesPerRow: n,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
    }()

    /// Renders the whole composition.
    /// - Parameters:
    ///   - dark: render the dark-appearance variant.
    ///   - scale: 1 = canvas pixel size, 2 = @2x, fractions for the preview.
    ///   - imageProvider: resolves a layer to its bitmap for this appearance.
    static func render(project: Project,
                       dark: Bool,
                       scale: CGFloat,
                       imageProvider: (ShotLayer) -> CGImage?) -> CGImage? {
        let W = CGFloat(project.canvas.width) * scale
        let H = CGFloat(project.canvas.height) * scale
        guard W >= 2, H >= 2, W < 20000, H < 20000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(W.rounded()), height: Int(H.rounded()),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let full = CGRect(x: 0, y: 0, width: W, height: H)
        drawBackdrop(ctx, project.backdrop, dark: dark, in: full, scale: scale)

        // Layout: padding, then an optional caption band.
        let pad = project.backdrop.paddingFraction * min(W, H)
        var content = full.insetBy(dx: pad, dy: pad)
        var captionRect: CGRect?
        let captionText = project.caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !captionText.isEmpty {
            let fontSize = max(6, project.caption.sizeFraction * H)
            let band = fontSize * 2.1
            switch project.caption.placement {
            case .above:  // top of the canvas — CG origin is bottom-left
                captionRect = CGRect(x: pad, y: full.maxY - pad - band,
                                     width: content.width, height: band)
                content.size.height -= band
            case .below:
                captionRect = CGRect(x: pad, y: pad, width: content.width, height: band)
                content.origin.y += band
                content.size.height -= band
            }
        }
        guard content.width > 4, content.height > 4 else { return ctx.makeImage() }

        for layer in project.layers {
            guard let img = imageProvider(layer) else { continue }
            drawLayer(ctx, layer: layer, image: img, content: content,
                      canvas: full, scale: scale)
        }

        if let captionRect {
            drawCaption(ctx, project: project, dark: dark, text: captionText,
                        in: captionRect, canvasHeight: H)
        }

        return ctx.makeImage()
    }

    // MARK: - Backdrop

    private static func drawBackdrop(_ ctx: CGContext, _ backdrop: BackdropSettings,
                                     dark: Bool, in rect: CGRect, scale: CGFloat) {
        let (a, b) = backdrop.resolvedColors(dark: dark)
        if backdrop.kind == .solid || a == b {
            ctx.setFillColor(a.cg)
            ctx.fill(rect)
        } else if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                            colors: [a.cg, b.cg] as CFArray,
                                            locations: [0, 1]) {
            switch backdrop.shape {
            case .linear:
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: rect.minX, y: rect.maxY),
                                       end: CGPoint(x: rect.maxX, y: rect.minY),
                                       options: [])
            case .radial:
                let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.08)
                let radius = hypot(rect.width, rect.height) * 0.62
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius,
                                       options: [.drawsAfterEndLocation])
            }
        }

        if backdrop.grain, let noise = noiseTile {
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.setAlpha(dark ? 0.08 : 0.06)
            ctx.setBlendMode(.overlay)
            // Tile size proportional to render scale so the grain looks the
            // same in the preview and in the export.
            ctx.draw(noise, in: CGRect(x: 0, y: 0, width: 96 * scale, height: 96 * scale),
                     byTiling: true)
            ctx.restoreGState()
        }
    }

    // MARK: - Layers

    private static func drawLayer(_ ctx: CGContext, layer: ShotLayer, image: CGImage,
                                  content: CGRect, canvas: CGRect, scale: CGFloat) {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        guard iw > 0, ih > 0 else { return }

        // Base size: aspect-fit the window into 78% of the content area,
        // then apply the layer's own scale.
        let fit = min(content.width * 0.78 / iw, content.height * 0.78 / ih)
        let dw = iw * fit * layer.scale
        let dh = ih * fit * layer.scale
        guard dw > 1, dh > 1 else { return }

        let center = CGPoint(x: content.midX + layer.offsetX * canvas.width,
                             y: content.midY - layer.offsetY * canvas.height)

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: -layer.rotation * .pi / 180)  // UI: positive = clockwise

        let rect = CGRect(x: -dw / 2, y: -dh / 2, width: dw, height: dh)
        let radius = min(layer.cornerRadius * scale, dw / 2, dh / 2)

        if layer.shadowOpacity > 0.01 {
            ctx.setShadow(offset: CGSize(width: 0, height: -layer.shadowOffsetY * scale),
                          blur: layer.shadowRadius * scale,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0,
                                         alpha: layer.shadowOpacity))
        }
        // Transparency layer: the rounded clip happens inside the group, the
        // shadow is applied to the group's silhouette — so transparent window
        // corners cast a correctly shaped shadow.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if radius > 0.5 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius,
                               cornerHeight: radius, transform: nil))
            ctx.clip()
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // MARK: - Caption

    /// Automatic caption color: dark ink on light backdrops, near-white on
    /// dark ones — so the dark render inverts it naturally.
    static func captionColor(project: Project, dark: Bool) -> NSColor {
        let (a, b) = project.backdrop.resolvedColors(dark: dark)
        let lum = (a.luminance + b.luminance) / 2
        return lum > 0.55
            ? NSColor(srgbRed: 0.10, green: 0.10, blue: 0.13, alpha: 1)
            : NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    }

    private static func drawCaption(_ ctx: CGContext, project: Project, dark: Bool,
                                    text: String, in rect: CGRect, canvasHeight: CGFloat) {
        let fontSize = max(6, project.caption.sizeFraction * canvasHeight)
        let weight: NSFont.Weight = switch project.caption.weight {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: captionColor(project: project, dark: dark),
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let size = attributed.size()
        attributed.draw(at: CGPoint(x: rect.midX - size.width / 2,
                                    y: rect.midY - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
