#!/bin/zsh
set -euo pipefail

checks=(
  '192\.168\.0\.(120|121|122)'
  'bot''01'
  '/Users/''felix'
  '0305''3311'
  '^-----BEGIN (RSA|OPENSSH|EC) PRIVATE KEY-----'
  '\bmac12''0\b'
  '\bmac12''2\b'
  'DELL ''24'
)

failed=0
is_binary_path() {
  [[ "$1" == ./scripts/check-public-tree.sh ]] && return 0
  [[ "$1" == docs/images/*.png || "$1" == docs/images/*.jpg ||
    "$1" == docs/images/*.jpeg || "$1" == docs/images/*.webp ||
    "$1" == ./docs/images/*.png || "$1" == ./docs/images/*.jpg ||
    "$1" == ./docs/images/*.jpeg || "$1" == ./docs/images/*.webp ]]
}

for pattern in "${checks[@]}"; do
  while IFS= read -r match; do
    file="${match%%:*}"
    if is_binary_path "$file"; then
      continue
    fi
    print -r -- "$match"
    print -u2 "Public-tree check failed: $pattern"
    failed=1
  done < <(rg -n --hidden \
    --glob '!.git/**' \
    --glob '!.git' \
    --glob '!node_modules/**' \
    --glob '!dist/**' \
    --glob '!.build*/**' \
    --glob '!**/.build*/**' \
    --glob '!.playwright-cli/**' \
    --glob '!output/**' \
    --glob '!docs/superpowers/**' \
    "$pattern" . || true)
done

if [[ -d docs/superpowers && "${PUBLIC_TREE_ALLOW_PREP_DOCS:-0}" != "1" ]]; then
  print -u2 "Public-tree check failed: private preparation docs are present"
  failed=1
fi

large_files="$(find . -path ./.git -prune -o -path ./node_modules -prune \
  -o -path ./dist -prune -o -path ./.build-tests -prune \
  -o -path ./.build-ci -prune -o -path ./.build -prune \
  -o -path '*/native/.build' -prune -o -path ./bin -prune \
  -o -type f -size +10M -print)"
if [[ -n "$large_files" ]]; then
  print -u2 "Files larger than 10 MiB:"
  print -u2 "$large_files"
  failed=1
fi

exit "$failed"

