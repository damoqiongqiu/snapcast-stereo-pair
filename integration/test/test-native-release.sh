#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
mode="${1:-release}"

cd "$repo_root"
swift test --package-path native
integration/test/test-install-lifecycle.sh
integration/test/test-audio-profile.sh
integration/test/test-deployment-target.sh
integration/test/test-fifo-reader-resilience.sh
integration/test/test-fifo-resilience.sh
integration/test/test-health-check.sh
integration/test/test-public-tree-privacy.sh
integration/test/test-watchdog-recovery.sh
integration/test/test-native-app-packaging.sh
integration/test/test-homebrew-formula.sh
integration/scripts/check-deployment-target.sh
zsh -n integration/scripts/*.sh integration/test/*.sh
plutil -lint integration/launchagents/*.plist.in >/dev/null
./scripts/check-public-tree.sh

if [[ "$mode" == "--automated-only" ]]; then
  print "Native release automated checks passed"
  exit 0
fi

report="${SNAPCAST_HARDWARE_ACCEPTANCE_FILE:-}"
[[ -n "$report" && -f "$report" ]] || {
  print -u2 "A two-Mac hardware acceptance record is required for release."
  print -u2 "Set SNAPCAST_HARDWARE_ACCEPTANCE_FILE to a completed report."
  exit 1
}

for section in \
  "Mac models and operating systems" \
  "Stereo-pair mode" \
  "System mode" \
  "Remote offline" \
  "Sleep and wake" \
  "Crash recovery" \
  "Meters and synchronization" \
  "Localization and accessibility" \
  "Diagnostics privacy"; do
  grep -Fq "## $section" "$report" || {
    print -u2 "Hardware report is missing section: $section"
    exit 1
  }
done

print "Native release checks passed, including the hardware acceptance record"
