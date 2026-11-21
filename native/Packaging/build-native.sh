#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
swift build --package-path "$repo_root/native" -c release --product StereoPairAgent
swift build --package-path "$repo_root/native" -c release --product mac-stereo-pairctl
