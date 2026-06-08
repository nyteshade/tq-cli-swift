# frozen_string_literal: true

class Tq < Formula
  desc "TOON query & mutation tool — jq for the TOON format"
  homepage "https://github.com/YOUR_USERNAME/tq"
  url "https://github.com/YOUR_USERNAME/tq/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  depends_on :xcode => ["16.0", :build]
  depends_on :macos => :ventura

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/tq"
  end

  test do
    (testpath/"test.toon").write "name: Ada\nage: 36\n"
    output = shell_output("#{bin}/tq .name test.toon").strip
    assert_equal "Ada", output
  end
end
