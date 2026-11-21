#!/bin/zsh
set -euo pipefail

helper_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ -n "${SNAPCAST_SOURCE_ROOT:-}" ]]; then
  repo_root="$SNAPCAST_SOURCE_ROOT"
elif [[ -f "$helper_dir/../source-root" ]]; then
  IFS= read -r repo_root < "$helper_dir/../source-root"
else
  repo_root="$(cd "$helper_dir/../.." && pwd)"
fi
[[ -x "$repo_root/integration/scripts/install-local.sh" ]]
source "$repo_root/integration/scripts/pair-config.sh"

validate_remote_user() {
  [[ "$1" =~ '^[A-Za-z0-9._-]{1,64}$' ]]
}

validate_remote_host() {
  [[ "$1" =~ '^([A-Za-z0-9][A-Za-z0-9.-]{0,251}|\[[0-9A-Fa-f:]+\])$' ]]
}

install_local() {
  "$repo_root/integration/scripts/install-native.sh"
  "$repo_root/integration/scripts/install-local.sh"
  print
  print "Local stereo-pair runtime installation completed."
}

configure_remote() {
  local remote_user="$1"
  local remote_host="$2"
  local key_path="$HOME/.ssh/id_ed25519"

  validate_remote_user "$remote_user" || {
    print -u2 "Invalid remote user."
    exit 2
  }
  validate_remote_host "$remote_host" || {
    print -u2 "Invalid remote host."
    exit 2
  }

  PAIR_NONINTERACTIVE=1 \
  REMOTE_USER="$remote_user" \
  REMOTE_HOST="$remote_host" \
  LEFT_IS_REMOTE="${LEFT_IS_REMOTE:-true}" \
    /bin/zsh "$repo_root/integration/scripts/configure-pair.sh" --force

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  if [[ ! -f "$key_path" ]]; then
    /usr/bin/ssh-keygen -t ed25519 -N "" -f "$key_path"
  fi

  if ! /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=3 \
    "$remote_user@$remote_host" true >/dev/null 2>&1; then
    print "Remote password is required by ssh-copy-id. It is not read by this app."
    /usr/bin/ssh-copy-id -i "$key_path.pub" "$remote_user@$remote_host"
  fi

  /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=3 \
    "$remote_user@$remote_host" true >/dev/null

  "$repo_root/integration/scripts/install-native.sh"
  "$repo_root/integration/scripts/install-local.sh"
  "$repo_root/integration/scripts/install-remote.sh"
  print
  print "Remote stereo-pair setup completed."
}

case "${1:-}" in
  install-local)
    install_local
    ;;
  configure-remote)
    [[ $# -eq 3 ]] || {
      print -u2 "Usage: $0 configure-remote USER HOST"
      exit 2
    }
    configure_remote "$2" "$3"
    ;;
  *)
    print -u2 "Usage: $0 {install-local|configure-remote USER HOST}"
    exit 2
    ;;
esac
