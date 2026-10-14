# Assessments

## FileKit

[FileKit](https://github.com/nvzqz/FileKit) wraps file paths and file
operations (a `Path` type, operators for copy/move/symlink, typed `File`
reads and writes).

**Not adopting it.** Lines barely touches the file system directly:

- Documents are read and written by SwiftUI's document system, which also
  provides autosave, Versions, and the Open/Save panels.
- The remaining file access is a handful of one-line `Data(contentsOf:)`
  reads (placing images, importing dropped SVGs) and the export writer.
  `URL` and `FileManager` already cover these.
- The project's README still lists compatibility from the Swift 2 / Xcode 7
  era and its GitHub page shows no releases. A dependency here would add
  risk for no real gain.

Revisit only if Lines grows real file management (a library of drawings, a
watched folder, batch export).

## Accessibility

An audit of the app for VoiceOver, keyboard use, and motion
settings. [Capable](https://github.com/chrs1885/Capable) reports which
accessibility settings are on. SwiftUI already exposes those through the
environment (`accessibilityReduceMotion` and others) and
`NSWorkspace`, so it isn't needed.

### Already in place

- Icon-only buttons have text labels (through `Button(title, systemImage:)`)
  and tooltips, and every toolbar item is also in the menu bar with a shortcut.
- Scrub fields, the version scrubber, and the code panel's divider support
  VoiceOver's adjust actions.
- Layer rows combine into one element with a label, a hidden state,
  selection, and Show/Hide and Rename actions.
- Colour wells, the background pill, and the welcome drop target have labels
  and values.

### Fixed in this pass

- **Graph nodes:** VoiceOver can now reach each node. It reads the node's
  name and kind, its details (type, units, "used by"), and the preview
  description as a hint. Each node has Select and Show on Canvas actions.
- **Timeline bars:** each animation now reads its property and timing
  ("begins at 0.50s, lasts 2.00s, repeats forever"). Select works, and
  adjusting nudges when it begins.
- **Canvas:** the canvas now reads the document name and its element count,
  with a hint to use the Layers panel. Selecting an element on the canvas
  announces it ("Selected canopy", or "3 selected").
- **Reduce Motion:** palette icons stop animating, panels appear without
  sliding, and Tidy Up stops gliding.
- **Decorative bits:** the palette's corner triangles are hidden from
  VoiceOver; the slot's "More Options" action covers them.

### Still worth doing

- The drawing itself is web content. VoiceOver can't step through shapes on
  the canvas; the Layers panel is the accessible route. A future step could
  label SVG elements with ARIA roles from their `<title>`.
- Dragging on the canvas (moving, resizing, corner radius, gradient handles)
  has keyboard equivalents for moving (arrow keys) and for exact values (the
  inspector), but not for the handles themselves.

## Translation

Lines uses Apple's String Catalogs: `Support/Localizable.xcstrings` holds
every string the app shows (about 390). `just strings` refreshes it from the
sources, and the build compiles it into `<language>.lproj` folders inside the
app, where SwiftUI finds them.

To add a language, open the catalog in Xcode, add the language and translate
it. Drawing names and the SVG itself are never translated.

[swift-localization](https://github.com/TelemTobi/swift-localization) adds
type-safe accessors on top of string catalogs. SwiftUI's string literals
already look up translations directly, so it isn't needed.
