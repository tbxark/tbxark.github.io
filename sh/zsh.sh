#!/usr/bin/env bash
#
# zsh.sh - Install zsh, make it the login shell and drop in a ~/.zshrc (Debian/Ubuntu).
#
#   * installs zsh through apt-get when it is missing
#   * sets zsh as the default shell for the target user
#   * replaces ~/.zshrc with https://www.tbxark.com/sh/zshrc (backing up the old one)
#
# Source: https://github.com/TBXark/tbxark.github.io/blob/master/sh/zsh.sh

set -Eeuo pipefail

readonly PROG="zsh.sh"
readonly DEFAULT_ZSHRC_URL="https://www.tbxark.com/sh/zshrc"

usage() {
  cat <<'EOF'
Install zsh, set it as the default shell and install ~/.zshrc (Debian/Ubuntu).

USAGE
  curl -fsSL https://www.tbxark.com/sh/zsh.sh | sudo bash
  curl -fsSL https://www.tbxark.com/sh/zsh.sh | sudo bash -s -- deploy -y
  sudo ./zsh.sh [system-user]

ARGUMENTS
  [system-user]   Local account to configure
                  (default: $SUDO_USER, falling back to root)

OPTIONS
  -t, --target <name>   Same as [system-user]
  -f, --file <path>     Install this local file as ~/.zshrc instead of downloading
  -U, --url <url>       Download ~/.zshrc from this URL
  -S, --skip-shell      Install zsh and ~/.zshrc, but do not change the login shell
  -R, --keep-zshrc      Do not touch an existing ~/.zshrc
  -n, --dry-run         Print the planned changes without applying them
  -y, --yes             Skip the confirmation prompt
  -h, --help            Show this help

ENVIRONMENT
  TARGET_USER, ZSHRC_URL, ZSHRC_FILE, SKIP_SHELL=1, KEEP_ZSHRC=1, DRY_RUN=1, ASSUME_YES=1

EXAMPLES
  curl -fsSL https://www.tbxark.com/sh/zsh.sh | sudo bash -s -- -y
  curl -fsSL https://www.tbxark.com/sh/zsh.sh | sudo bash -s -- deploy --dry-run
  sudo ./zsh.sh --file ./zshrc
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

TARGET_USER="${TARGET_USER:-}"
ZSHRC_URL="${ZSHRC_URL:-$DEFAULT_ZSHRC_URL}"
ZSHRC_FILE="${ZSHRC_FILE:-}"
SKIP_SHELL="${SKIP_SHELL:-0}"
KEEP_ZSHRC="${KEEP_ZSHRC:-0}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)     TARGET_USER="${2:-}"; shift 2 ;;
    -f|--file)       ZSHRC_FILE="${2:-}"; shift 2 ;;
    -U|--url)        ZSHRC_URL="${2:-}"; ZSHRC_FILE=""; shift 2 ;;
    -S|--skip-shell) SKIP_SHELL=1; shift ;;
    -R|--keep-zshrc) KEEP_ZSHRC=1; shift ;;
    -n|--dry-run)    DRY_RUN=1; shift ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    --)              shift; POSITIONAL+=("$@"); break ;;
    -*)              usage >&2; die "unknown option: $1" ;;
    *)               POSITIONAL+=("$1"); shift ;;
  esac
done

[[ ${#POSITIONAL[@]} -ge 1 && -z "$TARGET_USER" ]] && TARGET_USER="${POSITIONAL[0]}"
: "${TARGET_USER:=${SUDO_USER:-root}}"

# When the script is run from a checkout, prefer the zshrc sitting next to it.
if [[ -z "$ZSHRC_FILE" && -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$SCRIPT_DIR/zshrc" ]] && ZSHRC_FILE="$SCRIPT_DIR/zshrc"
fi
[[ -n "$ZSHRC_FILE" && ! -r "$ZSHRC_FILE" ]] && die "cannot read zshrc file: $ZSHRC_FILE"

# --------------------------------------------------------------- environment

[[ "$(id -u)" -eq 0 ]] || die "must run as root, e.g. 'curl -fsSL ... | sudo bash'"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}:${ID_LIKE:-}" in
    debian:*|ubuntu:*|*:*debian*|*:*ubuntu*) : ;;
    *) warn "detected ${PRETTY_NAME:-an unknown distro}; this script targets Debian/Ubuntu" ;;
  esac
fi

getent passwd "$TARGET_USER" >/dev/null || die "no such local user: $TARGET_USER"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
CURRENT_SHELL="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "home directory missing for $TARGET_USER: $TARGET_HOME"

readonly ZSHRC="$TARGET_HOME/.zshrc"
readonly STAMP="$(date +%Y%m%d%H%M%S)"

log "Local user  : $TARGET_USER ($TARGET_HOME)"
log "Login shell : $CURRENT_SHELL -> $([[ "$SKIP_SHELL" == "1" ]] && echo 'unchanged (--skip-shell)' || echo 'zsh')"
if [[ "$KEEP_ZSHRC" == "1" && -f "$ZSHRC" ]]; then
  log "zshrc       : keeping the existing $ZSHRC (--keep-zshrc)"
elif [[ -n "$ZSHRC_FILE" ]]; then
  log "zshrc       : $ZSHRC_FILE -> $ZSHRC"
else
  log "zshrc       : $ZSHRC_URL -> $ZSHRC"
fi
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

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# --------------------------------------------------------------- 1. install zsh

ZSH_BIN="$(command -v zsh || true)"

if [[ -n "$ZSH_BIN" ]]; then
  ok "zsh already installed: $ZSH_BIN ($("$ZSH_BIN" --version))"
elif [[ "$DRY_RUN" == "1" ]]; then
  log "[dry-run] would run: apt-get update && apt-get install -y zsh"
  ZSH_BIN=/usr/bin/zsh
else
  command -v apt-get >/dev/null 2>&1 || die "apt-get not found; install zsh manually first"
  log "Installing zsh..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || warn "apt-get update failed, trying to install anyway"
  apt-get install -y --no-install-recommends zsh \
    || die "failed to install zsh"
  ZSH_BIN="$(command -v zsh || true)"
  [[ -n "$ZSH_BIN" ]] || die "zsh is still not on PATH after installation"
  ok "installed $("$ZSH_BIN" --version)"
fi

# --------------------------------------------------------------- 2. default shell

# chsh refuses shells that are not listed in /etc/shells.
ensure_in_shells() {
  local shell="$1"
  grep -qxF "$shell" /etc/shells 2>/dev/null && return 0
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] would add $shell to /etc/shells"
    return 0
  fi
  printf '%s\n' "$shell" >> /etc/shells
  ok "added $shell to /etc/shells"
}

if [[ "$SKIP_SHELL" == "1" ]]; then
  log "Leaving the login shell as $CURRENT_SHELL (--skip-shell)"
elif [[ "$CURRENT_SHELL" == "$ZSH_BIN" ]]; then
  ok "$TARGET_USER already uses $ZSH_BIN as login shell"
else
  ensure_in_shells "$ZSH_BIN"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] would set the login shell of $TARGET_USER to $ZSH_BIN"
  else
    log "Setting the login shell of $TARGET_USER to $ZSH_BIN..."
    if chsh -s "$ZSH_BIN" "$TARGET_USER" 2>/dev/null \
      || usermod -s "$ZSH_BIN" "$TARGET_USER"; then
      ok "login shell is now $(getent passwd "$TARGET_USER" | cut -d: -f7) (was $CURRENT_SHELL)"
    else
      die "could not change the login shell; run 'chsh -s $ZSH_BIN $TARGET_USER' manually"
    fi
  fi
fi

# --------------------------------------------------------------- 3. zshrc

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 1 --max-time 30 "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --tries=3 --timeout=30 "$1"
  else
    die "neither curl nor wget is available"
  fi
}

install_zshrc() {
  local new="$WORKDIR/zshrc"

  if [[ -n "$ZSHRC_FILE" ]]; then
    cat "$ZSHRC_FILE" > "$new"
  else
    log "Downloading $ZSHRC_URL ..."
    fetch "$ZSHRC_URL" > "$new" || die "failed to download $ZSHRC_URL"
  fi
  [[ -s "$new" ]] || die "the downloaded zshrc is empty; refusing to overwrite $ZSHRC"

  # A broken rc file would break every new login shell, so check it first.
  if [[ -x "$ZSH_BIN" ]] && ! "$ZSH_BIN" -n "$new"; then
    die "the new zshrc has a syntax error; $ZSHRC left untouched"
  fi

  if [[ -f "$ZSHRC" ]] && cmp -s "$new" "$ZSHRC"; then
    ok "$ZSHRC is already up to date"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] would write $ZSHRC ($(wc -l < "$new" | tr -d ' ') lines)"
    [[ -f "$ZSHRC" ]] && log "[dry-run] would back it up to $ZSHRC.bak.$STAMP"
    return 0
  fi

  if [[ -f "$ZSHRC" ]]; then
    cp -a "$ZSHRC" "$ZSHRC.bak.$STAMP"
    warn "backed up the previous rc file to $ZSHRC.bak.$STAMP"
  fi
  install -m 644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$new" "$ZSHRC"
  ok "wrote $ZSHRC ($(wc -l < "$ZSHRC" | tr -d ' ') lines)"
}

if [[ "$KEEP_ZSHRC" == "1" && -f "$ZSHRC" ]]; then
  log "Keeping the existing $ZSHRC (--keep-zshrc)"
else
  install_zshrc
fi

# ~/.zshrc.local is sourced at the end of the rc file for machine specific bits.
if [[ "$DRY_RUN" != "1" && ! -e "$TARGET_HOME/.zshrc.local" ]]; then
  printf '# Machine specific zsh settings, sourced at the end of ~/.zshrc\n' \
    > "$WORKDIR/zshrc.local"
  install -m 644 -o "$TARGET_USER" -g "$TARGET_GROUP" \
    "$WORKDIR/zshrc.local" "$TARGET_HOME/.zshrc.local"
  ok "created $TARGET_HOME/.zshrc.local for local overrides"
fi

# --------------------------------------------------------------- 4. summary

echo
if [[ "$DRY_RUN" == "1" ]]; then
  ok "dry run finished, nothing was changed"
  exit 0
fi
ok "Done."
printf '      shell : %s\n' "$(getent passwd "$TARGET_USER" | cut -d: -f7)"
printf '      rc    : %s\n' "$ZSHRC"
printf '      local : %s\n' "$TARGET_HOME/.zshrc.local"
echo
log "Start using it now with:  exec $ZSH_BIN -l"
log "A new SSH session will pick up the new login shell automatically."
