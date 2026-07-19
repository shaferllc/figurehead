# Figurehead

*Figurehead — the carved figure at the bow of a ship; the part built to be
looked at.*

Figurehead is a promo-screenshot composer for Mac apps, in the spirit of
BeautyShot. It captures one or more app windows crisp and shadow-free,
stages them on a branded gradient backdrop with your own shadow, rounding,
and headline, and renders light **and** dark marketing shots in one export —
sized for the App Store, your website, or a social card.

Its sibling [snapyard](../snapyard) is the general screenshot
annotate-and-beautify tool; Figurehead is deliberately narrower — it is only
the promo-shot composer for app windows.

## Features

- **Window capture** via ScreenCaptureKit: pick any on-screen window from a
  list, captured at 2x with the system shadow suppressed and rounded corners
  kept transparent — compositing adds its own tunable shadow instead.
  Re-capture a layer with one click after you tweak the app.
- **Import instead** (⌘O, or drop a PNG on the canvas) if you captured the
  window elsewhere.
- **Stacked composites**: up to several window layers with one-click
  arrangements — Single, Duo (staggered pair), Fan (three windows) — plus
  per-layer scale, X/Y offset, subtle rotation (±6°), shadow radius /
  opacity / y-offset, and corner rounding.
- **Backdrops**: six gradient presets (each with a hand-picked dark twin),
  custom two-color gradient, solid fills, linear or radial shape, optional
  subtle grain, and a padding control.
- **Caption line**: an optional headline above or below the composition, with
  SF weight picker and size control. Its color is automatic — dark ink on
  light backdrops, light ink on dark — so it inverts correctly in the dark
  render.
- **Canvas presets**: 2560 × 1600, 1440 × 900, App Store 2880 × 1800,
  Twitter/OG 1200 × 630, or any custom size.
- **Light + dark in one go** (⌘E): exports `shot-light.png`,
  `shot-light@2x.png`, `shot-dark.png`, `shot-dark@2x.png` to a folder you
  choose. The dark variant flips each backdrop to its dark counterpart
  (custom colors get a darkened transform) and inverts the caption ink. A
  layer can hold an optional separate dark-mode capture; without one the dark
  render reuses the light capture.
- **⌘C** copies the current preview; the preview is the same CoreGraphics
  render the exporter uses, so it is exactly what ships.
- **Projects** (⌘S / ⌘⇧O): a `.figurehead` folder holding `project.json`
  plus the captured PNGs — styling survives restarts, captures included.

## Not yet

- No automatic app-language or appearance switching: to make a localized or
  dark-mode shot, switch the target app yourself and hit Re-capture. That is
  a deliberate, honest limitation — macOS offers no safe way to flip another
  app's language.
- No per-layer thumbnails in the window picker.
- Export is PNG only (no JPEG/WebP), and always renders all four variants.

## Build

```sh
./make-app.sh   # builds, signs ad-hoc, installs to /Applications, launches
```

Or during development: `swift build && swift run Figurehead`.

## Permissions

- **Screen Recording** — required for listing and capturing windows
  (ScreenCaptureKit). Figurehead detects a missing grant and shows an
  explainer with an Open System Settings button: System Settings →
  Privacy & Security → Screen Recording. macOS applies the grant on the
  app's **next launch**, so relaunch Figurehead after enabling it.

Nothing else: no network, no Accessibility, no Apple Events.
