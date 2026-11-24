#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
target="${SNAPCAST_DEPLOYMENT_TARGET:-14.0}"
deps_dir="$repo_root/.build/deps"
archive="$deps_dir/portaudio-19.7.0.tar.gz"
source_dir="$deps_dir/portaudio-src"
build_dir="$deps_dir/portaudio-build"
install_dir="$deps_dir/portaudio"
url="https://files.portaudio.com/archives/pa_stable_v190700_20210406.tgz"
sha256="47efbf42c77c19a05d22e627d42873e991ec0c1357219c0d74ce6a2948cb2def"

if [[ -f "$install_dir/lib/libportaudio.a" &&
  -f "$install_dir/.deployment-target" &&
  "$(cat "$install_dir/.deployment-target")" == "$target" ]]; then
  print "PortAudio compatibility build already available for macOS $target"
  exit 0
fi

mkdir -p "$deps_dir"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --silent --show-error "$url" --output "$archive"
fi
print -r -- "$sha256  $archive" | shasum -a 256 -c - >/dev/null

rm -rf "$source_dir" "$build_dir" "$install_dir"
mkdir -p "$source_dir"
tar -xzf "$archive" --strip-components=1 -C "$source_dir"
cmake -S "$source_dir" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$target" \
  -DCMAKE_INSTALL_PREFIX="$install_dir" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DPA_BUILD_SHARED=OFF \
  -DPA_BUILD_STATIC=ON \
  -DPA_USE_COREAUDIO=ON
cmake --build "$build_dir" --target install
print -r -- "$target" > "$install_dir/.deployment-target"
print "Built PortAudio for macOS deployment target $target"
