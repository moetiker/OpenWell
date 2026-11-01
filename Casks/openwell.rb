# Homebrew cask for OpenWell. This repository is its own tap.
cask "openwell" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

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
