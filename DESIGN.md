---
name: "deskView()"
description: "A native Mac camera studio in cool ink and Liquid Glass."
colors:
  canvas: "rgb(4% 6.5% 9%)"
  shell: "rgb(7.5% 11.5% 16%)"
  accent: "rgb(59% 85% 93%)"
  secondary: "rgb(68% 75% 82%)"
  record: "rgb(100% 34% 31%)"
  record-fill: "rgb(78% 12% 10%)"
  white: "#ffffff"
  black: "#000000"
typography:
  headline:
    fontFamily: "SF Pro"
    fontSize: "24pt"
    fontWeight: 600
  title:
    fontFamily: "SF Pro"
    fontSize: "14pt"
    fontWeight: 600
  body:
    fontFamily: "SF Pro"
    fontSize: "12pt"
    fontWeight: 400
  label:
    fontFamily: "SF Pro"
    fontSize: "12pt"
    fontWeight: 500
  caption:
    fontFamily: "SF Pro"
    fontSize: "11pt"
    fontWeight: 400
  micro:
    fontFamily: "SF Pro"
    fontSize: "10pt"
    fontWeight: 400
  layout-label:
    fontFamily: "SF Pro"
    fontSize: "10pt"
    fontWeight: 500
  record-label:
    fontFamily: "SF Pro"
    fontSize: "15pt"
    fontWeight: 600
  status:
    fontFamily: "SF Pro"
    fontSize: "11pt"
    fontWeight: 500
  timecode:
    fontFamily: "SF Mono"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  field: "6pt"
  control: "9pt"
  canvas: "12pt"
  shelf: "20pt"
spacing:
  "4": "4pt"
  "6": "6pt"
  "8": "8pt"
  "10": "10pt"
  "12": "12pt"
  "14": "14pt"
  "16": "16pt"
  "18": "18pt"
  "20": "20pt"
  "24": "24pt"
components:
  button-record:
    backgroundColor: "{colors.record-fill}"
    textColor: "{colors.white}"
    typography: "{typography.record-label}"
    height: "58pt"
    width: "116pt"
  button-snapshot:
    height: "44pt"
    width: "44pt"
  layout-item:
    textColor: "{colors.white}"
    typography: "{typography.layout-label}"
    rounded: "{rounded.control}"
    height: "58pt"
  layout-item-selected:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.canvas}"
    typography: "{typography.layout-label}"
    rounded: "{rounded.control}"
    height: "58pt"
  transport-shelf:
    rounded: "{rounded.shelf}"
    padding: "{spacing.14}"
    height: "92pt"
  source-preview:
    backgroundColor: "rgb(0 0 0 / 30%)"
    rounded: "{rounded.control}"
    height: "112pt"
  composed-preview:
    backgroundColor: "rgb(0 0 0 / 30%)"
    rounded: "{rounded.canvas}"
  status-pill:
    typography: "{typography.status}"
    padding: "6pt 10pt"
  demo-source-field:
    backgroundColor: "rgb(100% 100% 100% / 6%)"
    textColor: "{colors.secondary}"
    typography: "{typography.body}"
    rounded: "{rounded.field}"
    padding: "6pt 9pt"
---

# Design System: deskView()

## Overview

**Creative North Star: "Blue-hour drawing studio"**

A native Mac studio seen at blue hour: deep ink around the image, cool translucent Liquid Glass controls, clear system type, and a warm red recording action. The interface feels precise and quiet so camera content carries the attention. SwiftUI and native Liquid Glass are confirmed product choices.

Use the standard Mac vocabulary of buttons, pickers, sliders, menus, keyboard shortcuts, sheets and resizable windows. Glass groups operating controls; the source and framing panels use native material. FoyerKit owns the welcome experience. The approved first studio expression is Canvas first, recorded in `.impeccable/surfaces/studio.md`; its composition is not a requirement for every future sheet or utility window.

**Key Characteristics:**

- Cool ink work surfaces and an ice accent.
- A dominant composed image with quiet supporting controls.
- Grouped native Liquid Glass and material panels.
- Compact system typography, with monospaced timing.
- Explicit recording, hardware, permission and demo states.

## Colors

Cool ink and ice frame the content; warm recording color has a specific operational role. Frontmatter color strings translate the normalized RGB constants in `StudioTheme` without rounding them to seed swatches. They are the normative palette.

### Primary

- **Ice** (`colors.accent`): selection, source symbols, control tint and supporting actions. A selected layout uses ink text on this fill.

### Secondary

- **Recording signal** (`colors.record`): the recording status pill and its symbol.
- **Record fill** (`colors.record-fill`): the Record/Stop capsule behind white text and symbols. Its darker fill preserves the warm red role with stronger text contrast.

### Neutral

- **Deep ink** (`colors.canvas`): the workspace around the composed preview and foreground of selected layouts.
- **Blue charcoal** (`colors.shell`): the studio shell beneath native materials.
- **Cool secondary type** (`colors.secondary`): supporting copy, status messages and unavailable-source placeholders.
- **White** (`colors.white`): primary control content and unselected layout labels. Much ordinary text inherits the native foreground style.
- **Black** (`colors.black`): clean output background and translucent preview wells. The component tokens record the wells' opacity.

Green availability, orange warnings/demo status and cyan FoyerKit tint are native semantic colors. Do not substitute CSS named colors or guessed hex values for `Color.green`, `Color.orange` or `Color.cyan`.

**The Record Role Rule.** Reserve the warm red family for the recording action and recording status. The filled Record button uses the darker record-fill token with white content; the brighter record token identifies recording status.

## Typography

**Display and body font:** SF Pro through SwiftUI `.system` and native semantic font styles. There is no separate decorative display face.

**Timing font:** the native system monospaced design, SF Mono on macOS. Line height, tracking, font metrics and native-control typography remain system managed; the app does not specify replacements.

The character is compact, readable and operational. The extracted roles are observed sizes, not a modular scale to extrapolate.

### Hierarchy

- **Headline** (`typography.headline`): the Studio heading.
- **Title** (`typography.title`): Sources, Framing and setup-guide step headings.
- **Body** (`typography.body`): inspector rows, zoom values and explanatory guide copy.
- **Label** (`typography.label`): source labels, recording filenames and the output-format menu.
- **Caption** (`typography.caption`): footer status, pan labels and small utility actions.
- **Micro** (`typography.micro`): helper copy and source placeholders.
- **Layout label** (`typography.layout-label`): the layout choices on the transport shelf.
- **Record label** (`typography.record-label`): Record, Stop and Saving….
- **Status** (`typography.status`): labeled status pills.
- **Timecode** (`typography.timecode`): the recording timer.

The app title uses a local 19-point semibold treatment; the empty-canvas message uses 23-point medium type. Sheets use native `.title2.bold()`, and FoyerKit supplies its own welcome typography. The output-format label is proportional system type; the current source does not use monospaced dimensions or frame-rate labels. The clean demo output watermark uses native `.caption.monospaced()`.

**The Native Type Rule.** Use SwiftUI system typography and SF Symbols. Keep monospaced type for timing and explicit technical overlays; do not turn the studio into a type specimen.

## Layout

The approved studio expression is Canvas first: a sources sidebar, an expanding composed-image workspace, a framing inspector and a grouped transport shelf beneath the image. The surface brief and approved image remain the composition authority in `.impeccable/surfaces/studio.md` and `.impeccable/mocks/studio-a.png`.

The implementation has a 224-point sources panel and 232-point inspector, with native dividers between the regions. The header is 62 points high and reserves leading space for native window controls; the footer is 36 points high. Panel content uses `spacing.18`, the workspace uses `spacing.20`, the main workspace stack uses `spacing.16`, and the glass shelf uses `spacing.14`. Small control groups use the tighter extracted spacing steps. The source also has local 5-, 7-, 9- and 17-point gaps; there is no strict eight-point grid.

The studio defaults to 1440 × 900 points and has a 1120 × 740-point minimum. Both side panels scroll vertically. Resizing preserves the three regions and reduces the center workspace; no alternate mobile topology or width breakpoint is implemented. The composed image fits its available well while preserving its output aspect ratio, so letterboxing is expected. The well itself fills the available workspace height; it is not a fixed 16:9 box. Source thumbnails fill and clip within their smaller preview wells.

The output window defaults to 960 × 540 points with a 480 × 270-point minimum and a black, aspect-fitting image surface. The recordings sheet is 760 × 500 points; the setup guide is 700 points wide; Settings uses a 520-point window. These are native window and sheet constraints, not web breakpoints.

## Elevation & Depth

Depth comes from native materials and restrained tonal separation. The header and side panels use `.ultraThinMaterial`. The transport shelf uses `.glassEffect(.regular, in: RoundedRectangle(...))`, and Snapshot uses `.buttonStyle(.glass)`. The workspace stays a quiet ink field with darker image wells. Native dividers define the seams.

The sampled app views define no custom shadow tokens, painted blur values or custom transition curves. Liquid Glass, bordered controls, focus treatment and material appearance are supplied by macOS. FoyerKit explicitly disables its launch animation; no custom animation vocabulary is established here. Keep live previews steady and preserve native accessibility and Reduce Motion behavior when extending the interface.

**The Grouped Glass Rule.** Apply native glass to a functional group or control. Use native material for supporting panels; do not stack decorative glass cards around the camera image.

## Shapes

Use the extracted `rounded.field` for demo source rows, `rounded.control` for source thumbnails and layout selections, `rounded.canvas` for the composed-preview well, and `rounded.shelf` for the transport group. Preserve native rounded rectangles rather than inventing a second corner vocabulary.

Record and status pills use SwiftUI `Capsule()`. The microphone track also uses capsules. Their silhouette is semantic and has no fabricated fixed-radius token. Standard buttons, segmented pickers, switches, sliders and sheets retain their platform shapes. The recording image remains aspect fitted inside the clipped preview well.

## Components

### Recording and snapshot controls

Record is the warm, explicit action in the transport group. Its label frame is recorded by `components.button-record`; the filled background is a capsule using `colors.record-fill`, and the foreground is white. Record changes to Stop with a stop symbol while recording, shows a monospaced timer, and changes its label to Saving… while finishing. Capture availability dims the fill to 30 percent when idle and unavailable. Saving disables the control; recording keeps Stop available.

Snapshot is a native glass button with a camera symbol. `components.button-snapshot` describes its label frame, not any extra metrics supplied by the native button style. It is disabled when capture is unavailable. Hover, focus, pressed and disabled treatment remain native; the source establishes no custom interaction paint.

The header uses native bordered buttons; the empty canvas uses a bordered prominent preview/recovery action; small utility actions use link, borderless or plain button styles as observed. Keep the semantic control and its keyboard/help text.

### Layout selection and transport shelf

The shelf is a single regular-glass group containing four equal-width plain layout buttons, a divider, Snapshot and Record. The selected layout uses the Ice fill and ink foreground; unselected layouts use white labels with no custom fill. Each choice combines an SF Symbol with a short label and exposes selected accessibility state. Layout editing is disabled while busy. The tokens describe the shared frame, type and corners; the native glass effect stays in the sidecar.

### Sources and framing inputs

Sources combine a labeled native picker, an availability symbol and a clipped image preview. Available sources show a green checkmark; missing frames use a dotted circle and an accessibility label. Preview wells use `components.source-preview`; live thumbnails fill their wells. Demo rows use `components.demo-source-field` and explicit demo names rather than editable device pickers.

Framing uses a native segmented source picker, sliders for zoom and pan, a small switch for Mirror, rotation buttons and a link-style reset action. Picture-in-picture adds a native position picker, inset slider and Swap views action. These controls use standard macOS focus and disabled behavior; no bespoke text-field, slider-track or focus-ring system is defined.

### Status and recovery

`components.status-pill` is a capsule with a symbol, text and a 12-percent wash of its semantic foreground color. Recording uses the recording signal; active preview uses native green; demo mode uses native orange. Status is conveyed by wording and symbols as well as color. Footer status and the save-folder action remain visible at the bottom of the studio.

The empty canvas offers Start preview or a permission-recovery action, then connection help and an explicit demo choice. Unavailable effects remain disabled and explain that macOS and hardware determine support. Native alerts, sheets and `ContentUnavailableView` provide supporting recovery and library states.

### Clean output and onboarding

The output window contains the composed image on black and a stopped-preview recovery message when needed. Demo output carries a visible DEMO TEST CHART watermark. Studio framing-grid lines are a preview overlay; they do not define an exported graphic style.

FoyerKit owns the welcome flow with native cyan tint and SF Symbols. Preserve the required dependency and its native presentation; do not rebuild it as a custom marketing screen.

## Do's and Don'ts

### Do:

- **Do** preserve the cool ink palette and the separate Record fill and recording-status roles.
- **Do** use native SwiftUI controls, SF Symbols and FoyerKit onboarding.
- **Do** preserve the approved Canvas-first studio hierarchy while allowing sheets and utility windows to follow their native task.
- **Do** keep recording, saving, unavailable-source and permission states explicit in text and symbols.
- **Do** label test charts as demo content and keep illustrative mockup photography out of production previews.
- **Do** keep live previews steady and use native motion and accessibility behavior.

### Don't:

- **Don't** replace native Liquid Glass with a painted blur, decorative gradient or neon glow.
- **Don't** add decorative glass cards or invented telemetry around the canvas.
- **Don't** represent a missing or unsupported camera effect as available.
- **Don't** replace semantic controls and keyboard commands with decorative imitations.
- **Don't** infer a mobile layout, CSS breakpoint, fixed system-color hex value or custom shadow from this native implementation.
