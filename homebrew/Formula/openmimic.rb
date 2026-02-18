class Openmimic < Formula
  desc "Local, privacy-first workflow apprentice that generates AI-executable SOPs"
  homepage "https://github.com/sandroandric/OpenMimic"
  url "https://github.com/sandroandric/OpenMimic/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "PLACEHOLDER"
  license "MIT"

  depends_on "rust" => :build
  depends_on "python@3.12"
  depends_on "node" => :build

  def install
    # Build Rust binaries
    system "cargo", "build", "--release", "-p", "oc-apprentice-daemon"
    system "cargo", "build", "--release", "-p", "openmimic-cli"
    bin.install "target/release/oc-apprentice-daemon"
    bin.install "target/release/openmimic"

    # Install worker
    libexec.install "worker"

    # Install extension
    (libexec/"extension").install Dir["extension/src/*"]
    (libexec/"extension").install "extension/manifest.json"

    # Install launchd plists
    (libexec/"launchd").install Dir["resources/launchd/*.plist"]

    # Install uninstaller
    (libexec/"scripts").install "scripts/uninstall.sh"
  end

  def post_install
    # Create data directories
    (var/"oc-apprentice/logs").mkpath
    (var/"oc-apprentice/artifacts").mkpath
  end

  def caveats
    <<~EOS
      After installation, run:
        openmimic doctor

      To start services:
        openmimic start all

      You will need to grant:
        1. Accessibility permission in System Settings > Privacy & Security
        2. Screen Recording permission in System Settings > Privacy & Security

      To load the Chrome extension:
        1. Open chrome://extensions
        2. Enable Developer Mode
        3. Click "Load unpacked" and select: #{libexec}/extension/
    EOS
  end

  service do
    run [opt_bin/"oc-apprentice-daemon"]
    keep_alive crashed: true
    log_path var/"oc-apprentice/logs/daemon.log"
    error_log_path var/"oc-apprentice/logs/daemon.error.log"
  end
end
