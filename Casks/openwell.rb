# Homebrew cask for OpenWell. This repository is its own tap.
cask "openwell" do
  version "0.1.0"
  sha256 "9ca565f79f93b1594bb103d4be2da3fed002c838eff85333f5ae51816efe1ed2"

  url "https://github.com/moetiker/OpenWell/releases/download/v#{version}/OpenWell-#{version}.zip"
  name "OpenWell"
  desc "Opens terminal windows from the Dock on a free spot of the screen"
  homepage "https://github.com/moetiker/OpenWell"

  depends_on macos: :ventura

  app "OpenWell.app"

  uninstall quit: "ch.oetiker.OpenWell"

  zap trash: [
    "~/Library/Application Support/OpenWell",
    "~/Library/Caches/ch.oetiker.OpenWell",
  ]

  caveats <<~EOS
    OpenWell needs Accessibility access. On the first start, allow it under
    System Settings > Privacy & Security > Accessibility. If OpenWell is not
    in the list, add #{appdir}/OpenWell.app with the plus button.
  EOS
end
