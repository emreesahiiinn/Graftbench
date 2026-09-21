cask "graftbench" do
  version "0.1.0"
  sha256 "cf540810998ed223ba41d47c59f72b825a604cb80fea334c9ff37b75014c3971"

  url "https://github.com/emreesahiiinn/Graftbench/releases/download/v#{version}/Graftbench.dmg"
  name "Graftbench"
  desc "A faster, sharper Git client for macOS"
  homepage "https://github.com/emreesahiiinn/Graftbench"

  # Bump `version` + `sha256` on each release (the .sha256 asset has the hash).
  livecheck do
    url :url
    strategy :github_latest
  end

  app "Graftbench.app"

  caveats <<~EOS
    Graftbench is ad-hoc signed (not notarized). If macOS blocks it, run:
      xattr -dr com.apple.quarantine "#{appdir}/Graftbench.app"
  EOS
end
