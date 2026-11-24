#!/bin/zsh

app_was_running=false
app_lifecycle_path() {
  print -r -- "${SNAPCAST_APP_PATH:-$HOME/Applications/MacBook Stereo Pair.app}"
}

app_lifecycle_pgrep() {
  print -r -- "${SNAPCAST_PGREP_BIN:-/usr/bin/pgrep}"
}

app_is_running() {
  local app_path
  app_path="$(app_lifecycle_path)"
  "$(app_lifecycle_pgrep)" -f "$app_path/Contents/MacOS/MacStereoPair" >/dev/null 2>&1
}

stop_running_app() {
  local app_path osascript_bin pkill_bin
  app_path="$(app_lifecycle_path)"
  osascript_bin="${SNAPCAST_OSASCRIPT_BIN:-/usr/bin/osascript}"
  pkill_bin="${SNAPCAST_PKILL_BIN:-/usr/bin/pkill}"
  app_was_running=false
  if ! app_is_running; then
    return 0
  fi

  app_was_running=true
  "$osascript_bin" -e 'tell application "MacBook Stereo Pair" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    app_is_running || return 0
    sleep 0.25
  done

  "$pkill_bin" -TERM -f "$app_path/Contents/MacOS/MacStereoPair" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    app_is_running || return 0
    sleep 0.25
  done
  return 1
}

start_app_if_running() {
  local app_path open_bin
  app_path="$(app_lifecycle_path)"
  open_bin="${SNAPCAST_OPEN_BIN:-/usr/bin/open}"
  if [[ "$app_was_running" == "true" ]]; then
    "$open_bin" "$app_path"
  fi
  app_was_running=false
}
