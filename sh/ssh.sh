#!/usr/bin/env bash
#
# ssh.sh - Install GitHub SSH public keys and harden sshd on Debian/Ubuntu.
#
#   * fetches https://github.com/<user>.keys into ~/.ssh/authorized_keys
#   * enables public key auth and disables password auth
#   * validates the config and restarts the SSH service
#
# Source: https://github.com/TBXark/tbxark.github.io/blob/master/ssh.sh
#
# WARNING: keep your current SSH session open until you have verified that
#          key-based login works from a second terminal.

set -Eeuo pipefail

readonly PROG="ssh.sh"
readonly KEYS_URL_BASE="https://github.com"

usage() {
  cat <<'EOF'
Install your GitHub SSH keys and disable password login (Debian/Ubuntu).

USAGE
  curl -fsSL https://www.tbxark.com/ssh.sh | sudo bash -s -- <github-user> [system-user]
  sudo ./ssh.sh <github-user> [system-user]

ARGUMENTS
  <github-user>   GitHub account whose public keys are installed (required)
  [system-user]   Local account to install them for
                  (default: $SUDO_USER, falling back to root)

OPTIONS
  -u, --user <name>     Same as <github-user>
  -t, --target <name>   Same as [system-user]
  -n, --dry-run         Print the planned changes without applying them
  -r, --replace         Overwrite authorized_keys instead of appending
  -y, --yes             Skip the confirmation prompt
  -h, --help            Show this help

ENVIRONMENT
  GITHUB_USER, TARGET_USER, DRY_RUN=1, REPLACE_KEYS=1, ASSUME_YES=1

EXAMPLES
  curl -fsSL https://www.tbxark.com/ssh.sh | sudo bash -s -- tbxark
  curl -fsSL https://www.tbxark.com/ssh.sh | sudo bash -s -- tbxark deploy -y
  curl -fsSL https://www.tbxark.com/ssh.sh | sudo bash -s -- tbxark --dry-run
EOF
}

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLU=$'\033[34m'; RST=$'\033[0m'
else
  RED=''; GRN=''; YLW=''; BLU=''; RST=''
fi
log()  { printf '%s==>%s %s\n' "$BLU" "$RST" "$*"; }
ok()   { printf '%s  ok%s  %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s  !%s   %s\n' "$YLW" "$RST" "$*" >&2; }
die()  { printf '%s  x%s   %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

# --------------------------------------------------------------- arguments

GH_USER="${GITHUB_USER:-}"
TARGET_USER="${TARGET_USER:-}"
DRY_RUN="${DRY_RUN:-0}"
REPLACE_KEYS="${REPLACE_KEYS:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user)    GH_USER="${2:-}"; shift 2 ;;
    -t|--target)  TARGET_USER="${2:-}"; shift 2 ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -r|--replace) REPLACE_KEYS=1; shift ;;
    -y|--yes)     ASSUME_YES=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    --)           shift; POSITIONAL+=("$@"); break ;;
    -*)           usage >&2; die "unknown option: $1" ;;
    *)            POSITIONAL+=("$1"); shift ;;
  esac
done

[[ ${#POSITIONAL[@]} -ge 1 && -z "$GH_USER" ]]     && GH_USER="${POSITIONAL[0]}"
[[ ${#POSITIONAL[@]} -ge 2 && -z "$TARGET_USER" ]] && TARGET_USER="${POSITIONAL[1]}"
: "${TARGET_USER:=${SUDO_USER:-root}}"

if [[ -z "$GH_USER" ]]; then
  usage >&2
  die "missing <github-user>"
fi
[[ "$GH_USER" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]] \
  || die "invalid GitHub username: $GH_USER"

# --------------------------------------------------------------- environment

[[ "$(id -u)" -eq 0 ]] || die "must run as root, e.g. 'curl -fsSL ... | sudo bash -s -- $GH_USER'"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}:${ID_LIKE:-}" in
    debian:*|ubuntu:*|*:*debian*|*:*ubuntu*) : ;;
    *) warn "detected ${PRETTY_NAME:-an unknown distro}; this script targets Debian/Ubuntu" ;;
  esac
fi

SSHD_BIN="$(command -v sshd || true)"
[[ -n "$SSHD_BIN" ]] || { [[ -x /usr/sbin/sshd ]] && SSHD_BIN=/usr/sbin/sshd; }
[[ -n "$SSHD_BIN" ]] || die "sshd not found; install it first: apt-get install -y openssh-server"

getent passwd "$TARGET_USER" >/dev/null || die "no such local user: $TARGET_USER"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "home directory missing for $TARGET_USER: $TARGET_HOME"

readonly SSHD_CONFIG=/etc/ssh/sshd_config
readonly SSHD_CONFIG_D=/etc/ssh/sshd_config.d
# sshd keeps the FIRST value it sees for a keyword, the Include line sits at the
# top of sshd_config, and drop-ins are read in lexical order. The 00- prefix
# therefore wins over stock files such as 50-cloud-init.conf.
readonly DROPIN="$SSHD_CONFIG_D/00-harden-auth.conf"
readonly STAMP="$(date +%Y%m%d%H%M%S)"

log "GitHub keys : ${KEYS_URL_BASE}/${GH_USER}.keys"
log "Local user  : $TARGET_USER ($TARGET_HOME)"
log "Result      : public key login enabled, password login disabled"
[[ "$DRY_RUN" == "1" ]] && warn "dry run: nothing will be written" || true

if [[ "$DRY_RUN" != "1" && "$ASSUME_YES" != "1" ]]; then
  # stdin is the curl pipe, so ask on the terminal directly; if there is no
  # terminal (CI, cloud-init) just continue.
  if [[ -r /dev/tty ]]; then
    printf '%s  ?%s   Continue? [y/N] ' "$YLW" "$RST" >&2
    reply=""
    read -r reply < /dev/tty || reply=""
    case "$reply" in
      [yY]|[yY][eE][sS]) ;;
      *) die "aborted" ;;
    esac
  else
    warn "no terminal available, continuing without confirmation"
  fi
fi

# --------------------------------------------------------------- 1. fetch keys

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 1 --max-time 30 "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --tries=3 --timeout=30 "$1"
  else
    die "neither curl nor wget is available"
  fi
}

log "Fetching public keys from GitHub..."
RAW_KEYS="$(fetch "${KEYS_URL_BASE}/${GH_USER}.keys")" \
  || die "failed to fetch keys; check the network and the username"
[[ -n "${RAW_KEYS//[[:space:]]/}" ]] \
  || die "GitHub user '$GH_USER' has no public keys; aborting so you don't lock yourself out"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
NEW_KEYS="$WORKDIR/new_keys"
: > "$NEW_KEYS"

while IFS= read -r line; do
  [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
  printf '%s\n' "$line" > "$WORKDIR/one"
  if ssh-keygen -l -f "$WORKDIR/one" >/dev/null 2>&1; then
    printf '%s github:%s\n' "$line" "$GH_USER" >> "$NEW_KEYS"
  else
    warn "skipping unrecognised key line: ${line:0:40}..."
  fi
done <<< "$RAW_KEYS"

KEY_COUNT="$(wc -l < "$NEW_KEYS" | tr -d ' ')"
[[ "$KEY_COUNT" -gt 0 ]] || die "no valid public keys parsed; aborting"
ok "found $KEY_COUNT valid public key(s)"
ssh-keygen -l -f "$NEW_KEYS" 2>/dev/null | sed 's/^/      /' || true

# ------------------------------------------------- 2. write authorized_keys

SSH_DIR="$TARGET_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
MERGED="$WORKDIR/merged"

if [[ "$REPLACE_KEYS" == "1" || ! -f "$AUTH_KEYS" ]]; then
  cat "$NEW_KEYS" > "$MERGED"
else
  cat "$AUTH_KEYS" > "$MERGED"
  # make sure the existing file ends with a newline before appending
  if [[ -s "$MERGED" && "$(tail -c1 "$MERGED" | wc -l)" -eq 0 ]]; then
    echo >> "$MERGED"
  fi
  added=0
  while IFS= read -r key; do
    # dedupe on "type + base64 body", ignoring trailing comments
    sig="$(awk '{print $1" "$2}' <<< "$key")"
    grep -qF -- "$sig" "$MERGED" && continue
    printf '%s\n' "$key" >> "$MERGED"
    added=$((added + 1))
  done < "$NEW_KEYS"
  log "adding $added new key(s), the rest were already present"
fi

# safety gate: never disable passwords with an empty authorized_keys
[[ -s "$MERGED" ]] || die "authorized_keys would be empty; refusing to disable password login"

if [[ "$DRY_RUN" == "1" ]]; then
  log "[dry-run] would write $AUTH_KEYS:"
  sed 's/^/      /' "$MERGED"
else
  install -d -m 700 -o "$TARGET_USER" -g "$TARGET_GROUP" "$SSH_DIR"
  if [[ -f "$AUTH_KEYS" ]]; then
    cp -a "$AUTH_KEYS" "$AUTH_KEYS.bak.$STAMP"
  fi
  install -m 600 -o "$TARGET_USER" -g "$TARGET_GROUP" "$MERGED" "$AUTH_KEYS"
  ok "wrote $AUTH_KEYS ($(wc -l < "$AUTH_KEYS" | tr -d ' ') line(s))"
fi

# ------------------------------------------------- 3. sshd configuration

DIRECTIVES=(PasswordAuthentication PubkeyAuthentication ChallengeResponseAuthentication
            KbdInteractiveAuthentication PermitEmptyPasswords AuthenticationMethods)

comment_out() {
  local file="$1" d found=0 pattern tmp
  [[ -f "$file" ]] || return 0
  for d in "${DIRECTIVES[@]}"; do
    if grep -qiE "^[[:space:]]*${d}[[:space:]]" "$file"; then found=1; break; fi
  done
  [[ "$found" -eq 1 ]] || return 0

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] would comment out conflicting directives in $file"
    return 0
  fi
  cp -a "$file" "$file.bak.$STAMP"
  pattern="$(IFS='|'; echo "${DIRECTIVES[*]}")"
  tmp="$WORKDIR/$(basename "$file").rewritten"

  # awk rather than sed: no GNU-only flags needed, and the alternation pattern
  # cannot collide with a s/// delimiter.
  if ! awk -v pat="^[ \t]*(${pattern})[ \t]" -v tag="# [${PROG} ${STAMP}] " '
        { if (match(tolower($0), tolower(pat))) print tag $0; else print }
      ' "$file" > "$tmp"; then
    die "failed to rewrite $file; original left untouched (backup: $file.bak.$STAMP)"
  fi
  # never truncate a config down to nothing
  if [[ ! -s "$tmp" ]] || [[ "$(wc -l < "$tmp")" -ne "$(wc -l < "$file")" ]]; then
    die "refusing to write a suspicious rewrite of $file (backup: $file.bak.$STAMP)"
  fi
  # write through the existing inode so owner and mode are preserved
  cat "$tmp" > "$file"
  ok "commented out conflicting directives in $file (backup: $file.bak.$STAMP)"
}

log "Updating sshd configuration..."
comment_out "$SSHD_CONFIG"

USE_DROPIN=0
if grep -qiE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d/' "$SSHD_CONFIG" 2>/dev/null; then
  USE_DROPIN=1
  shopt -s nullglob
  for f in "$SSHD_CONFIG_D"/*.conf; do
    [[ "$f" == "$DROPIN" ]] && continue
    comment_out "$f"
  done
  shopt -u nullglob
fi

DROPIN_CONTENT="# Generated by ${PROG} at ${STAMP}
# Public key authentication on, password authentication off.
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
"
# Installing for root also requires root logins to be permitted (keys only).
if [[ "$TARGET_USER" == "root" ]]; then
  DROPIN_CONTENT+="PermitRootLogin prohibit-password
"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  if [[ "$USE_DROPIN" == "1" ]]; then
    log "[dry-run] would write $DROPIN:"
  else
    log "[dry-run] would append to $SSHD_CONFIG:"
  fi
  sed 's/^/      /' <<< "$DROPIN_CONTENT"
elif [[ "$USE_DROPIN" == "1" ]]; then
  install -d -m 755 "$SSHD_CONFIG_D"
  printf '%s' "$DROPIN_CONTENT" > "$DROPIN"
  chmod 600 "$DROPIN"
  ok "wrote drop-in config $DROPIN"
else
  cp -a "$SSHD_CONFIG" "$SSHD_CONFIG.bak.$STAMP"
  printf '\n%s' "$DROPIN_CONTENT" >> "$SSHD_CONFIG"
  ok "appended config to $SSHD_CONFIG (backup: $SSHD_CONFIG.bak.$STAMP)"
fi

# ------------------------------------------------- 4. validate and restart

rollback() {
  warn "rolling back configuration changes..."
  rm -f "$DROPIN"
  shopt -s nullglob
  for b in "$SSHD_CONFIG.bak.$STAMP" "$SSHD_CONFIG_D"/*.bak."$STAMP"; do
    [[ -f "$b" ]] || continue
    mv -f "$b" "${b%.bak.$STAMP}"
    warn "restored ${b%.bak.$STAMP}"
  done
  shopt -u nullglob
}

if [[ "$DRY_RUN" == "1" ]]; then
  log "[dry-run] skipping 'sshd -t' and the service restart"
  ok "dry run finished, nothing was changed"
  exit 0
fi

log "Validating configuration (sshd -t)..."
if ! "$SSHD_BIN" -t; then
  rollback
  die "sshd config validation failed; changes rolled back, service not restarted"
fi
ok "configuration is valid"

log "Restarting the SSH service..."
restarted=0
if command -v systemctl >/dev/null 2>&1; then
  # Ubuntu 22.10+ uses socket activation by default
  if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl restart ssh.socket || true
  fi
  for svc in ssh sshd; do
    if systemctl cat "${svc}.service" >/dev/null 2>&1; then
      # reload-or-restart keeps established connections alive where possible
      if systemctl reload-or-restart "${svc}.service"; then
        restarted=1; ok "systemctl reload-or-restart ${svc}"; break
      fi
    fi
  done
fi
if [[ "$restarted" -eq 0 ]]; then
  if service ssh restart 2>/dev/null || service sshd restart 2>/dev/null; then
    restarted=1; ok "service ssh restart"
  fi
fi
[[ "$restarted" -eq 1 ]] || die "could not restart SSH; run 'systemctl restart ssh' manually"

sleep 1
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null \
    || warn "service does not look active, check 'systemctl status ssh'"
fi

# ------------------------------------------------- 5. summary

echo
ok "Done. Effective authentication settings:"
"$SSHD_BIN" -T 2>/dev/null \
  | grep -iE '^(passwordauthentication|pubkeyauthentication|permitrootlogin|kbdinteractiveauthentication|permitemptypasswords|authorizedkeysfile) ' \
  | sed 's/^/      /'
echo
warn "Verify from a SECOND terminal before closing this session:"
printf '        ssh %s@<server-ip>\n' "$TARGET_USER"
warn "If login fails, roll back from this session with:"
printf '        rm -f %s && systemctl restart ssh\n' "$DROPIN"
printf '        # and restore any *.bak.%s files\n' "$STAMP"
