cask "lines" do
  version "1.0.0"
  sha256 :no_check

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
end
