#!/bin/zsh

pair_config_default_path() {
  print -r -- "${PAIR_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/snapcast-stereo-pair/pair.env}"
}

pair_interface_from_route() {
  print -r -- "$1" | awk '$1 == "interface:" { print $2; exit }'
}

detect_source_host() {
  local route_output="${1:-$(route -n get default 2>/dev/null || true)}"
  local interface
  interface="$(pair_interface_from_route "$route_output")"
  [[ -n "$interface" ]] || return 1
  ipconfig getifaddr "$interface" 2>/dev/null
}

load_pair_config() {
  local config_file
  local line
  local key
  local value
  local -a allowed=(
    CONFIG_SCHEMA
    REMOTE_USER
    REMOTE_HOST
    SOURCE_HOST
    LEFT_IS_REMOTE
    CAPTURE_DEVICE
    CAPTURE_DEVICE_UID
    LOCAL_OUTPUT_DEVICE
    NATIVE_OUTPUT_DEVICE_UID
    REMOTE_OUTPUT_DEVICE_UID
    LOCAL_CLIENT_ID
    REMOTE_CLIENT_ID
  )

  config_file="$(pair_config_default_path)"
  if [[ -f "$config_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      key="${line%%=*}"
      value="${line#*=}"
      value="${value#\"}"
      value="${value%\"}"
      if (( ${allowed[(Ie)$key]} == 0 )) || [[ -n "${(P)key+x}" ]]; then
        continue
      fi
      export "$key=$value"
    done < "$config_file"
  fi

  REMOTE_USER="${REMOTE_USER:-}"
  CONFIG_SCHEMA="${CONFIG_SCHEMA:-1}"
  REMOTE_HOST="${REMOTE_HOST:-}"
  SOURCE_HOST="${SOURCE_HOST:-}"
  LEFT_IS_REMOTE="${LEFT_IS_REMOTE:-true}"
  CAPTURE_DEVICE="${CAPTURE_DEVICE:-BlackHole 2ch}"
  CAPTURE_DEVICE_UID="${CAPTURE_DEVICE_UID:-BlackHole2ch_UID}"
  LOCAL_OUTPUT_DEVICE="${LOCAL_OUTPUT_DEVICE:-BuiltInSpeakerDevice}"
  NATIVE_OUTPUT_DEVICE_UID="${NATIVE_OUTPUT_DEVICE_UID:-BuiltInSpeakerDevice}"
  REMOTE_OUTPUT_DEVICE_UID="${REMOTE_OUTPUT_DEVICE_UID:-BuiltInSpeakerDevice}"
  LOCAL_CLIENT_ID="${LOCAL_CLIENT_ID:-stereo-local}"
  REMOTE_CLIENT_ID="${REMOTE_CLIENT_ID:-stereo-remote}"
  compute_pair_roles
}

compute_pair_roles() {
  if [[ "$LEFT_IS_REMOTE" == "true" ]]; then
    LEFT_CLIENT_ID="$REMOTE_CLIENT_ID"
    RIGHT_CLIENT_ID="$LOCAL_CLIENT_ID"
  else
    LEFT_CLIENT_ID="$LOCAL_CLIENT_ID"
    RIGHT_CLIENT_ID="$REMOTE_CLIENT_ID"
  fi
}

validate_pair_config_schema() {
  [[ "${CONFIG_SCHEMA:-1}" == <-> ]] &&
    (( CONFIG_SCHEMA >= 1 && CONFIG_SCHEMA <= 1 ))
}

migrate_pair_config_schema() {
  validate_pair_config_schema || {
    print -u2 "pair.env was created by a newer, unsupported version."
    return 1
  }
  CONFIG_SCHEMA=1
  save_pair_config
}

require_pair_config() {
  local -a missing=()
  [[ -n "$REMOTE_USER" ]] || missing+=(REMOTE_USER)
  [[ -n "$REMOTE_HOST" ]] || missing+=(REMOTE_HOST)
  [[ "$LEFT_IS_REMOTE" == "true" || "$LEFT_IS_REMOTE" == "false" ]] || missing+=(LEFT_IS_REMOTE)
  if (( ${#missing[@]} > 0 )); then
    print -u2 "Missing or invalid pair configuration: ${(j:, :)missing}"
    return 1
  fi
}

prepare_local_only_config() {
  REMOTE_USER="${REMOTE_USER:-pending-remote}"
  REMOTE_HOST="${REMOTE_HOST:-pending.invalid}"
  SOURCE_HOST="${SOURCE_HOST:-$(detect_source_host || true)}"
  LEFT_IS_REMOTE="${LEFT_IS_REMOTE:-true}"
}

save_pair_config() {
  local config_file
  config_file="$(pair_config_default_path)"
  mkdir -p "${config_file:h}"
  chmod 700 "${config_file:h}"
  cat > "$config_file" <<EOF
CONFIG_SCHEMA="$CONFIG_SCHEMA"
REMOTE_USER="$REMOTE_USER"
REMOTE_HOST="$REMOTE_HOST"
SOURCE_HOST="$SOURCE_HOST"
LEFT_IS_REMOTE="$LEFT_IS_REMOTE"
CAPTURE_DEVICE="$CAPTURE_DEVICE"
CAPTURE_DEVICE_UID="$CAPTURE_DEVICE_UID"
LOCAL_OUTPUT_DEVICE="$LOCAL_OUTPUT_DEVICE"
NATIVE_OUTPUT_DEVICE_UID="$NATIVE_OUTPUT_DEVICE_UID"
REMOTE_OUTPUT_DEVICE_UID="$REMOTE_OUTPUT_DEVICE_UID"
LOCAL_CLIENT_ID="$LOCAL_CLIENT_ID"
REMOTE_CLIENT_ID="$REMOTE_CLIENT_ID"
EOF
  chmod 600 "$config_file"
}

render_pair_template() {
  local source_file="$1"
  local output_file="$2"
  local render_home="${PAIR_RENDER_HOME:-$HOME}"
  local support_dir="$render_home/Library/Application Support/Snapcast"
  local support_dir_url="${support_dir// /%20}"
  local log_dir="$render_home/Library/Logs/Snapcast"
  local homebrew_bin
  homebrew_bin="${PAIR_RENDER_HOMEBREW_BIN:-$(brew --prefix 2>/dev/null || print /opt/homebrew)/bin}"

  sed \
    -e "s|@SUPPORT_DIR@|$support_dir|g" \
    -e "s|@SUPPORT_DIR_URL@|$support_dir_url|g" \
    -e "s|@LOG_DIR@|$log_dir|g" \
    -e "s|@HOMEBREW_BIN@|$homebrew_bin|g" \
    -e "s|@LOCAL_CLIENT_ID@|$LOCAL_CLIENT_ID|g" \
    -e "s|@REMOTE_CLIENT_ID@|$REMOTE_CLIENT_ID|g" \
    -e "s|@LEFT_CLIENT_ID@|$LEFT_CLIENT_ID|g" \
    -e "s|@RIGHT_CLIENT_ID@|$RIGHT_CLIENT_ID|g" \
    -e "s|@LOCAL_OUTPUT_DEVICE@|$LOCAL_OUTPUT_DEVICE|g" \
    -e "s|@NATIVE_OUTPUT_DEVICE_UID@|$NATIVE_OUTPUT_DEVICE_UID|g" \
    -e "s|@REMOTE_OUTPUT_DEVICE_UID@|$REMOTE_OUTPUT_DEVICE_UID|g" \
    -e "s|@CAPTURE_DEVICE@|$CAPTURE_DEVICE|g" \
    -e "s|@CAPTURE_DEVICE_UID@|$CAPTURE_DEVICE_UID|g" \
    -e "s|@SOURCE_HOST@|$SOURCE_HOST|g" \
    "$source_file" > "$output_file"
}
