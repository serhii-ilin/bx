class Bx < Formula
  desc "Run coding agents in a macOS sandbox-exec profile"
  homepage "https://github.com/serhii-ilin/bx"
  # url and sha256 are updated by .github/workflows/release.yml on every release.
  url "https://github.com/serhii-ilin/bx/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "fde1f1d5019546f7b223caf3563fc6319159ae3a9069bb037c3c1922b098f93e"
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
    # `brew test` itself runs under sandbox-exec, which cannot apply a nested
    # profile, so only check the profile bx generates.
    (testpath/"ws").mkpath
    profile = shell_output("#{bin}/bx --no-config -w #{testpath}/ws --print-profile")
    assert_match "(subpath \"#{(testpath/"ws").realpath}\")", profile
  end
end
