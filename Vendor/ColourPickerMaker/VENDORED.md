# ColourPickerMaker (vendored)

Upstream: https://github.com/sturdysturge/SwiftUIColourPickerMaker
Commit: 98dfdaf8eb809f8dc5071a2ad48f464716c6dfc0 (2020-06-24), MIT license (see LICENSE.md).
Author: Rob Sturgeon.

Vendored so Lines can carry these fixes. Every change is marked `Lines patch:` in the source.

1. Canvas thumbs are positioned from the bound values. Upstream kept the position in
   private drag state starting at zero, so an existing colour showed in the wrong place.
2. Slider thumbs are positioned from the bound value scaled to the track. Upstream used
   the unscaled 0–1 value as a point offset.
3. `DirectionalDragModifier.init` no longer writes to state during view initialization.
4. Saturation × brightness canvases use the current hue as their background (that branch
   was unreachable).
5. Thumbs are a thin white ring with a shadow instead of a thick black-and-white ring.
6. The test target is removed from Package.swift (tests aren't vendored).
