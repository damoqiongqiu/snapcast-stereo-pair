#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
formula="$repo_root/packaging/homebrew/macbook-stereo-pair.rb"

[[ -f "$formula" ]]
ruby -c "$formula" >/dev/null

if command -v brew >/dev/null 2>&1; then
  brew style "$formula" >/dev/null
fi

print "Homebrew formula tests passed"
