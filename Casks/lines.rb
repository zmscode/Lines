cask "lines" do
  version "1.0.1"
  sha256 "02ef2d3d394ab75b6342477674050283f7cc73908b539d74b033ae08b697f047"

  url "https://github.com/zmscode/Lines/releases/download/v#{version}/Lines-#{version}.zip"
  name "Lines"
  desc "SVG viewer and editor"
  homepage "https://github.com/zmscode/Lines"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :golden_gate

  app "Lines.app"

  zap trash: [
    "~/Library/Caches/com.zms.Lines",
    "~/Library/HTTPStorages/com.zms.Lines",
    "~/Library/Preferences/com.zms.Lines.plist",
    "~/Library/Saved Application State/com.zms.Lines.savedState",
    "~/Library/WebKit/com.zms.Lines",
  ]

  # Until releases are notarized (see RELEASING.md), macOS needs approving
  # the app once. Remove this caveat with the first notarized release.
  caveats <<~EOS
    Lines isn't notarized yet, so macOS may refuse to open it at first.
    Approve it once in System Settings > Privacy & Security > Open Anyway,
    or run:
      xattr -dr com.apple.quarantine #{appdir}/Lines.app
  EOS
end
