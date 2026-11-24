#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

private_address="10.20.30.""40"
private_host="user@example-host.""local"
user_path="/Users/""private-user/project"

cat > "$tmp_dir/report.md" <<EOF
address=$private_address
host=$private_host
path=$user_path
EOF

set +e
output="$(PUBLIC_TREE_ROOT="$tmp_dir" "$repo_root/scripts/check-public-tree.sh" 2>&1)"
exit_code=$?
set -e

if [[ "$exit_code" -eq 0 ]]; then
  print -u2 "privacy scan unexpectedly accepted leaked deployment data"
  exit 1
fi

for expected in "$private_address" "$private_host" "$user_path"; do
  if [[ "$output" != *"$expected"* ]]; then
    print -u2 "privacy scan did not report: $expected"
    exit 1
  fi
done

print "Public-tree privacy test passed"
