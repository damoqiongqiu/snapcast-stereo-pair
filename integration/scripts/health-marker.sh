#!/bin/zsh

write_health_marker() {
  local output_path="$1"
  local success="$2"
  local exit_code="$3"
  local message="$4"
  local state_dir="${output_path:h}"
  local timestamp
  local temporary

  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
  timestamp="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
  temporary="$(mktemp "$state_dir/.health-marker.XXXXXX")"
  jq -n \
    --arg completedAt "$timestamp" \
    --argjson success "$success" \
    --argjson exitCode "$exit_code" \
    --arg message "$message" \
    '{completedAt:$completedAt, success:$success, exitCode:$exitCode, message:$message}' \
    > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$output_path"
}
