#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkfifo "$tmp_dir/left.pcm" "$tmp_dir/right.pcm"
cat > "$tmp_dir/snapserver.conf" <<EOF
[server]
threads = 2
mdns_enabled = false
datadir = $tmp_dir/data

[http]
enabled = true
bind_to_address = 127.0.0.1
port = 19280

[tcp-control]
enabled = false

[tcp-streaming]
enabled = true
bind_to_address = 127.0.0.1
port = 19204

[stream]
source = pipe://$tmp_dir/left.pcm?name=LeftAudio&mode=read
source = pipe://$tmp_dir/right.pcm?name=RightAudio&mode=read
sampleformat = 48000:24:1
codec = pcm
chunk_ms = 20
buffer = 200
EOF

mkdir -p "$tmp_dir/data"
"$repo_root/.build/bin/snapserver" -c "$tmp_dir/snapserver.conf" \
  >"$tmp_dir/server.log" 2>&1 &
server_pid=$!

held=false
for _ in {1..30}; do
  fds="$(lsof -p "$server_pid" 2>/dev/null | grep -E "$tmp_dir/(left|right)\\.pcm" || true)"
  if [[ "$(print -r -- "$fds" | grep -c 'FIFO')" -eq 2 ]]; then
    held=true
    break
  fi
  sleep 0.1
done

[[ "$held" == "true" ]] || {
  print -u2 "Snapserver did not keep both FIFO readers open without writers"
  exit 1
}

print "FIFO reader resilience test passed"
