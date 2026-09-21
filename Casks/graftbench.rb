cask "graftbench" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/emreesahiiinn/Graftbench/releases/download/v#{version}/Graftbench.dmg"
  name "Graftbench"
  desc "A faster, sharper Git client for macOS"
  homepage "https://github.com/emreesahiiinn/Graftbench"

  app "Graftbench.app"

  caveats <<~EOS
    Graftbench is ad-hoc signed (not notarized). If macOS blocks it, run:
      xattr -dr com.apple.quarantine "#{appdir}/Graftbench.app"
  EOS
end
