#!/bin/bash
set -Eeuo pipefail

log() { printf '\n%s\n' "$*"; }
die() { printf '\nError: %s\n' "$*" >&2; exit 1; }
trap 'printf "Bootstrap failed at line %s. Fix the issue and rerun the command.\n" "$LINENO" >&2' ERR

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || die 'Requires macOS on Apple Silicon.'
[[ "$(id -u)" != 0 ]] || die 'Run as your normal user, not root.'
[[ -t 0 ]] || die 'Run interactively in Terminal using the command in the README.'

readonly DOTFILES="$HOME/.dotfiles"
readonly REPO_URL='https://github.com/z11i/dotfiles.git'
readonly GH_VERSION='2.102.0'
readonly GH_SHA256='da922c20d1792e5b2cbf375593d7a658acf034c12c84e007e71c76ef959c337e'

if [[ -e "$DOTFILES" || -L "$DOTFILES" ]]; then
    die "$DOTFILES already exists. To resume an existing checkout, run: cd ~/.dotfiles && ./setup"
fi

if ! /usr/bin/xcode-select -p >/dev/null 2>&1 || ! /usr/bin/git --version >/dev/null 2>&1; then
    log 'Installing Apple Command Line Tools. Accept the macOS installation dialog; this script will wait.'
    /usr/bin/xcode-select --install || die 'Could not request Command Line Tools. Install them and rerun.'
    while ! /usr/bin/xcode-select -p >/dev/null 2>&1; do
        sleep 5
    done
    /usr/bin/git --version >/dev/null 2>&1 || die 'Command Line Tools are not ready. Finish installation and rerun.'
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bootstrap.XXXXXX")"
readonly WORK_DIR
trap 'rm -rf "$WORK_DIR"' EXIT

log "Downloading temporary GitHub CLI $GH_VERSION."
archive="gh_${GH_VERSION}_macOS_arm64.zip"
/usr/bin/curl --proto '=https' --tlsv1.2 -fLsS --retry 3 \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${archive}" \
    -o "$WORK_DIR/$archive"
actual_sha="$(/usr/bin/shasum -a 256 "$WORK_DIR/$archive")"
[[ "${actual_sha%% *}" == "$GH_SHA256" ]] || die 'GitHub CLI checksum mismatch.'
/usr/bin/ditto -x -k "$WORK_DIR/$archive" "$WORK_DIR"
GH="$WORK_DIR/gh_${GH_VERSION}_macOS_arm64/bin/gh"
readonly GH
[[ -x "$GH" ]] || die 'GitHub CLI executable missing from archive.'

if ! "$GH" auth status --hostname github.com >/dev/null 2>&1; then
    log 'Authorize this Mac using your phone:'
    log 'Open https://github.com/login/device on your phone and enter the code shown below.'
    BROWSER=/usr/bin/true "$GH" auth login --hostname github.com --git-protocol https --web
fi
"$GH" api repos/z11i/dotfiles --silent

log 'Cloning private dotfiles into ~/.dotfiles.'
/usr/bin/git -c credential.helper= \
    -c "credential.helper=!\"$GH\" auth git-credential" \
    clone "$REPO_URL" "$DOTFILES"

username="$(id -un)"
[[ "$username" =~ ^[a-zA-Z0-9._-]+$ ]] || die 'Unusual username; add it to home-manager/machines.nix manually, then run ./setup.'
machines="$DOTFILES/home-manager/machines.nix"
if ! awk -v user="$username" '
    /^[[:space:]]*#/ { next }
    { line=$0; sub(/^[[:space:]]*/, "", line)
      if (index(line, "\"" user "\"") == 1) {
          sub(/^"[^"]*"[[:space:]]*/, "", line)
          if (line ~ /^=/) found=1
      } else if (index(line, user) == 1) {
          line=substr(line, length(user)+1)
          if (line ~ /^[[:space:]]*=/) found=1
      }
    }
    END { exit !found }
' "$machines"; then
    log "Choose a profile for the new username '$username'."
    profile=''
    until [[ "$profile" == personal || "$profile" == work ]]; do
        read -r -p 'Profile (personal/work): ' profile
    done
    printf '\n// {\n  "%s" = { profile = "%s"; };\n}\n' "$username" "$profile" >> "$machines"
    log 'Added a local machines.nix entry. Commit it later if you want to retain it.'
fi

log 'Starting private dotfiles setup. Follow its installer and administrator prompts.'
(cd "$DOTFILES" && ./setup)

PERMANENT_GH="$HOME/.nix-profile/bin/gh"
[[ -x "$PERMANENT_GH" ]] || die 'Setup returned successfully but Home Manager gh is missing.'
"$PERMANENT_GH" auth setup-git --hostname github.com
log 'Setup complete. The temporary GitHub CLI will now be removed.'
