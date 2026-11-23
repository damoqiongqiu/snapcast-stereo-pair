#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$repo_root/.build"

command_names=(cmake ninja pkg-config clang)
if [[ -z "${SNAPCAST_BREW_PREFIX:-}" || -z "${SNAPCAST_PORTAUDIO_PREFIX:-}" ]]; then
  command_names+=(brew)
fi

for command_name in "${command_names[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    print -u2 "Missing build dependency: $command_name"
    exit 1
  fi
done

brew_prefix="${SNAPCAST_BREW_PREFIX:-$(brew --prefix)}"
portaudio_prefix="${SNAPCAST_PORTAUDIO_PREFIX:-$(brew --prefix portaudio)}"
export PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

cmake -S "$repo_root" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${SNAPCAST_DEPLOYMENT_TARGET:-14.0}" \
  -DBUILD_SERVER=ON \
  -DBUILD_CLIENT=ON \
  -DBUILD_WITH_SSL=OFF \
  -DBUILD_WITH_FLAC=OFF \
  -DBUILD_WITH_VORBIS=OFF \
  -DBUILD_WITH_OPUS=OFF \
  -DBUILD_WITH_AVAHI=OFF \
  -DBUILD_WITH_EXPAT=OFF \
  -DBUILD_WITH_ALSA=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_STATIC_LIBS=ON

cmake --build "$build_dir" -j "$(sysctl -n hw.logicalcpu)"

mkdir -p "$build_dir/bin"
install -m 755 "$repo_root/bin/snapserver" "$build_dir/bin/snapserver"
install -m 755 "$repo_root/bin/snapclient" "$build_dir/bin/snapclient"
clang -O2 -Wall -Wextra \
  -I"$portaudio_prefix/include" \
  -L"$portaudio_prefix/lib" \
  -Wl,-rpath,"$portaudio_prefix/lib" \
  -o "$build_dir/bin/capture-blackhole" \
  "$repo_root/integration/capture/capture-blackhole-pa.c" \
  "$repo_root/integration/capture/audio_metrics.c" \
  -lportaudio
clang -O2 -Wall -Wextra \
  -o "$build_dir/bin/set-audio-volume" \
  "$repo_root/integration/capture/set-audio-volume.c" \
  -framework CoreAudio \
  -framework CoreFoundation
clang -O2 -Wall -Wextra \
  -o "$build_dir/bin/wake-recovery-listener" \
  "$repo_root/integration/capture/wake-recovery-listener.c" \
  -framework CoreFoundation \
  -framework IOKit

print "Built:"
print "  $build_dir/bin/snapserver"
print "  $build_dir/bin/snapclient"
print "  $build_dir/bin/capture-blackhole"
print "  $build_dir/bin/set-audio-volume"
print "  $build_dir/bin/wake-recovery-listener"
