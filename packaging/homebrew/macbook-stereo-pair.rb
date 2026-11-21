# frozen_string_literal: true

# Homebrew formula for building the unofficial two-Mac stereo pair console.
class MacbookStereoPair < Formula
  desc "Two-Mac lossless stereo speaker runtime and native console"
  homepage "https://github.com/damoqiongqiu/snapcast-stereo-pair"
  license "GPL-3.0-or-later"
  head "https://github.com/damoqiongqiu/snapcast-stereo-pair.git", branch: "main"

  depends_on "cmake" => :build
  depends_on "ninja" => :build
  depends_on "pkgconf" => :build
  depends_on xcode: ["15.0", :build]
  depends_on "boost"
  depends_on "flac"
  depends_on "libogg"
  depends_on "libsoxr"
  depends_on "libvorbis"
  depends_on "openssl@4"
  depends_on "opus"
  depends_on "portaudio"
  depends_on "switchaudio-osx"

  def install
    ENV["SNAPCAST_BREW_PREFIX"] = HOMEBREW_PREFIX
    ENV["SNAPCAST_PORTAUDIO_PREFIX"] = formula_opt_prefix("portaudio")
    system "integration/scripts/build-macos.sh"
    system "native/Packaging/build-native.sh"
    system "native/Packaging/build-app.sh", "--output", buildpath/"MacBook Stereo Pair.app"

    prefix.install "MacBook Stereo Pair.app"
    bin.install "native/.build/release/mac-stereo-pairctl"
    bin.install ".build/bin/snapserver", ".build/bin/snapclient"
    pkgshare.install Dir["*"]
    pkgshare.install ".build", "native/.build"
  end

  def caveats
    <<~EOS
      Install the BlackHole 2ch audio driver separately:
        brew install --cask blackhole-2ch

      This build is ad-hoc signed and not notarized. It does not require an
      Apple Developer subscription. Copy the app to ~/Applications and launch
      it to run the first-time setup:
        cp -R "#{opt_prefix}/MacBook Stereo Pair.app" ~/Applications/
    EOS
  end

  test do
    assert_path_exists bin/"mac-stereo-pairctl"
    assert_predicate prefix/"MacBook Stereo Pair.app/Contents/MacOS/MacStereoPair", :executable?
  end
end
