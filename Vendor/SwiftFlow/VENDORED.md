# SwiftFlow (vendored)

Upstream: https://github.com/aaurelions/SwiftFlow
Tag v0.2.0, commit 588e3a172c32ab562e0e370c5df57d352dee96f5 (2026-09-10), MIT license (see LICENSE.md).

Vendored so Lines can carry this fix; changes are marked `Lines patch:`.

1. `Handle.isConnectable` is honoured: handles with it set to `false` no longer
   start a connection drag (upstream stored the flag but every handle got a drag
   target). They still accept drops, so input ports work as targets only.
2. The test target is removed from Package.swift (tests aren't vendored).
