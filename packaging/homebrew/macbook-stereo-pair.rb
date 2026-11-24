# typed: strict
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
  depends_on "libvorbis"
  depends_on "openssl@4"
  depends_on "opus"
  depends_on "portaudio"
  depends_on "switchaudio-osx"

  resource "portaudio" do
    url "https://files.portaudio.com/archives/pa_stable_v190700_20210406.tgz"
    sha256 "47efbf42c77c19a05d22e627d42873e991ec0c1357219c0d74ce6a2948cb2def"
  end

  def install
    ENV["SNAPCAST_BREW_PREFIX"] = HOMEBREW_PREFIX
    portaudio_prefix = buildpath/"portaudio-compat"
    resource("portaudio").stage do
      system "cmake", "-S", ".", "-B", "build", *std_cmake_args,
             "-DCMAKE_INSTALL_PREFIX=#{portaudio_prefix}",
             "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
             "-DPA_BUILD_SHARED=OFF",
             "-DPA_BUILD_STATIC=ON",
             "-DPA_USE_COREAUDIO=ON"
      system "cmake", "--build", "build", "--target", "install"
    end
    ENV["SNAPCAST_PORTAUDIO_STATIC"] = portaudio_prefix/"lib/libportaudio.a"
    ENV["SNAPCAST_PORTAUDIO_INCLUDE"] = portaudio_prefix/"include"
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
