cask "lines" do
  version "1.0.0"
  sha256 "d1f224dc53bd89e64751a46cfc9e0b2e8d561a7c8b0e40597ba2267f8ecb8627"

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
