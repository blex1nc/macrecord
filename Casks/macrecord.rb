# Homebrew cask for a personal tap (github.com/blex1nc/homebrew-macrecord).
# Update `version` and `sha256` (from SHA256SUMS in the release) on each release.
cask "macrecord" do
  version "0.1.0"
  sha256 :no_check # TODO: replace with the hash from SHA256SUMS after the first release

  url "https://github.com/blex1nc/macrecord/releases/download/v#{version}/macrecord.zip"
  name "macrecord"
  desc "Private, open-source macro recorder and autoclicker"
  homepage "https://github.com/blex1nc/macrecord"

  depends_on macos: ">= :sonoma"

  app "macrecord.app"

  # Not notarized (ad-hoc signed): clear the quarantine flag so Gatekeeper allows launch.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/macrecord.app"]
  end

  zap trash: [
    "~/Library/Application Support/macrecord",
    "~/Library/Preferences/io.github.blex1nc.macrecord.plist",
  ]
end
