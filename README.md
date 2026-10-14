# Lines

A native macOS SVG viewer and editor. Edit the source and the drawing side by side; changes in either one show up in the other.

## Build

Requires macOS 27 and Xcode 27 (`build.sh` uses it even if `xcode-select` points at the Command Line Tools).

```bash
just run              # build, quit any running copy, open the new build
just build            # release build → build/Lines.app (`just build debug` for debug)
just format           # swift-format with the project's .swift-format
```

`just` wraps `./build.sh [release|debug]`, which you can also run directly.

## Features

- **Welcome window.** When nothing's open, a quiet drop target with Open File… and New Drawing (⇧⌘1 brings it back; recents are in File › Open Recent).
- **Clean canvas.** A Photoshop-style tools palette on the left: Select (V), Hand (H), shape tools you drag to draw (R, O, L, P; Shift keeps them even, Option draws from the centre), Text (T), Image, and the background swatch (checkerboard, white, grey, black or a custom colour). Zoom buttons float at the bottom right and the minimap (with a zoom badge) at the bottom left.
- **Navigation.** Documents open fitted to the window and stay fitted as you resize until you zoom. The mouse wheel zooms around the cursor (⌘-scroll on a trackpad), pinch zooms, and a two-finger double-tap toggles Fit and Actual Size. Pan at any zoom with a middle-button drag, Space-drag, or two-finger scrolling. When the drawing doesn't fit, a minimap in the corner shows the visible region; click or drag in it to move around.
- **Source and canvas, side by side** (only the canvas is shown at first; ⌘1–3 switch layouts and ⌃⌘I shows the inspector). The editor has syntax highlighting and the system Find bar (⌘F). Moving the insertion point into a tag selects that element on the canvas, and selecting on the canvas highlights its tag in the source.
- **Direct manipulation.** Click to select, drag to move (Shift locks the axis), arrow keys nudge (Shift moves 10). Drag the selection's handles to resize (Shift keeps proportions, Option resizes from the centre) or its top handle to rotate (Shift snaps to 15°). Double-click text to edit it in place. Click a selected group to move it, double-click to select inside it. Esc selects the enclosing group.
- **Settings** (⌘,): appearance (Auto, Light, Dark), canvas background (including Transparent, which lets the desktop show through), new-window layout, and code themes: pick a dark and a light theme (Gruvbox, 0x96f, Catppuccin, One Dark Pro, Dracula, JetBrains, Monokai, VS Code Dark Modern, Ayu) and the editor follows the app's appearance.
- **Toolbar.** Panel toggles (Layers ⌘1, Inspector ⌥⌘I, Code ⌘2), a Canvas/Graph switch (⌘3) and Share.
- **Floating panels.** Layers and the inspector float over the viewer; the drawing fits and centres in the space they leave.
- **Layers panel.** The element tree, topmost first. Drag rows to reorder them or move them into another group, drag one to another app to copy it as SVG, or drop SVG files from the Finder to import them. Hovering a row highlights the element on the canvas; double-click a name to rename it (sets its `id`). Each row has a visibility toggle and a context menu, and the bar at the bottom adds shapes, groups and deletes.
- **Element graph** (⌘4). Elements as nodes, nesting as gray edges, and references (gradient fills, clip paths, masks, filters, `<use>`) as colored edges. Add gradients, clip paths, masks and filters from the graph's Add menu, then drag from their output to a shape's input to use them; delete an edge to remove it. Gradient nodes preview their colours and filter nodes list their effects; right-click a node for more. Double-click a node to show it on the canvas. The graph lays itself out as a tidy tree (Tidy Up resets it); scrolling zooms, and middle-drag or dragging empty space pans.
- **Colour picker.** Fill and stroke wells open a popover with a hue/saturation canvas, brightness and opacity sliders, a hex field, and the colours already in the drawing. Opacity is written as `fill-opacity` / `stroke-opacity`.
- **Inspector.** A header with the element's name and quick actions; position, size and rotation with scrubbable labels (drag a label to change its value) and an aspect lock; fill, stroke, opacity and corner radius; text font, size, weight and alignment; document size, viewBox and Fit to Content; raw attributes in a collapsed section.
- **Mac conventions.** A document-based app with autosave, Versions, and named undo ("Undo Move", "Undo Change Fill"). Edit menu Copy, Cut, Paste and Delete work on elements and paste as SVG markup. The toolbar is customizable. Shortcuts match Keynote (Arrange: ⌥⇧⌘F / ⌥⇧⌘B, Group ⌥⌘G).
- **Export** (⇧⌘E): SVG (optionally minified), PNG or JPEG at 1–4× (rendered by WebKit), or PDF. **Share** sends SVG or PNG. **Print** (⌘P) prints just the drawing.
- **Code panel** (⌘2): Format (⌃I) and Copy buttons, text size by pinch, ⌘+/⌘− or the header buttons; markup is re-indented after canvas edits and when you pause typing (Settings › Editor).

## How it fits together

| File | Role |
| --- | --- |
| `SVGDocument.swift` | The document (new SwiftUI `Document` protocol). The source text is the single source of truth; `replaceText` registers named, coalesced undo. |
| `CanvasHTML.swift` | The WebKit canvas: rendering, hit testing, dragging, and DOM edits, which are serialized back to text. |
| `CanvasController.swift` | The per-window bridge between SwiftUI, the canvas and the source editor. |
| `SyntaxTheme.swift` | Code colour themes, taken from each theme's Zed extension. |
| `SourceEditor.swift` | The NSTextView editor, highlighter, and start-tag scanner used for selection sync. |
| `InspectorView.swift` | The inspector form. |
| `LayersSidebar.swift` | The layers list (top-level elements are layers; groups disclose their contents). |
| `GraphView.swift` | The element graph, built on [SwiftFlow](https://github.com/aaurelions/SwiftFlow) (vendored in `Vendor/SwiftFlow` with a fix; see `VENDORED.md`). |
| `ColourPicker.swift` | The colour popover, built from ColourPickerMaker's canvas and sliders. |
| `Vendor/ColourPickerMaker` | [ColourPickerMaker](https://github.com/sturdysturge/SwiftUIColourPickerMaker) (MIT), vendored with fixes listed in `VENDORED.md`. |
