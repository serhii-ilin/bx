# Homebrew formula template. The release workflow fills in @VERSION@ and
# @SHA256@ and pushes the result to serhii-ilin/homebrew-tap as Formula/bx.rb.
class Bx < Formula
  desc "Run coding agents in a macOS sandbox-exec profile"
  homepage "https://github.com/serhii-ilin/bx"
  url "https://github.com/serhii-ilin/bx/archive/refs/tags/v@VERSION@.tar.gz"
  sha256 "@SHA256@"
  license "MIT"
  head "https://github.com/serhii-ilin/bx.git", branch: "main"

  depends_on :macos

  def install
    inreplace "bin/bx", /^BX_VERSION=".*"$/, "BX_VERSION=\"#{version}\""
    bin.install "bin/bx"
    pkgshare.install "examples/config"
  end

  def caveats
    <<~EOS
      bx works without a config file. To customise it:
        mkdir -p ~/.config/bx && cp #{opt_pkgshare}/config ~/.config/bx/config
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/bx --version")
    (testpath/"ws").mkpath
    system bin/"bx", "--no-config", "-w", testpath/"ws", "sh", "-c", "echo ok > ws/out"
    assert_equal "ok\n", (testpath/"ws/out").read
  end
end
