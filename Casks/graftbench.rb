cask "graftbench" do
  version "0.2.0"
  sha256 "77652e54c5e69a56a930cef5c6b6058e7b8f1e2662e066c15d009fa17bfdc505"

  url "https://github.com/emreesahiiinn/Graftbench/releases/download/v#{version}/Graftbench.dmg"
  name "Graftbench"
  desc "A faster, sharper Git client for macOS"
  homepage "https://github.com/emreesahiiinn/Graftbench"

  # Bump `version` + `sha256` on each release (the .sha256 asset has the hash).
  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true

  app "Graftbench.app"

  caveats <<~EOS
    Graftbench is ad-hoc signed (not notarized). If macOS blocks it, run:
      xattr -dr com.apple.quarantine "#{appdir}/Graftbench.app"
  EOS
end
