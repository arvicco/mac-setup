#!/bin/bash
# install-ssh-controller.sh — SSH-mode bootstrap (runs on the controller).
#
# Mirrors install-gui.sh (GUI mode, runs on target) but for SSH mode.
# Automates target-side prep that would otherwise require lots of typing:
# pubkey install, NOPASSWD sudo, Xcode CLT, disabling auto-updates. Then
# rsyncs this repo and runs bin/setup over SSH.
#
# On the TARGET Mac, before running this script, do these manually:
#   1. Complete macOS first-boot wizard (create "admin" user)
#   2. System Settings -> General -> Sharing -> turn on Remote Login
#
# Then from the CONTROLLER:
#   ./install-ssh-controller.sh <target-ip> [bin/setup flags...]
#
# Example:
#   ./install-ssh-controller.sh 192.168.1.50 \
#     --hostname my-mac \
#     --git-name "Jane Doe" \
#     --git-email jane@example.com
#
# After this completes, log into the target graphically and run:
#   cd ~/mac-setup && ./install-ssh-target.sh
# to finalize the few GUI-only steps (default browser, SSH keychain).
#
# Safe to re-run. Every step is idempotent.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <target-ip> [--hostname X --git-name X --git-email X ...]" >&2
  exit 1
fi

TARGET_IP="$1"
shift
SETUP_ARGS=("$@")

TARGET_USER="${MAC_SETUP_TARGET_USER:-admin}"
TARGET_HOST="$TARGET_USER@$TARGET_IP"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!!  %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERR %s\033[0m\n' "$*" >&2; exit 1; }

SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=6
)

# ---------------------------------------------------------------- 1. Reach
info "Checking SSH access to $TARGET_HOST..."
if ! ssh "${SSH_OPTS[@]}" -o BatchMode=no "$TARGET_HOST" "true" 2>/dev/null; then
  # Reachable-with-password? ssh-copy-id will prompt; that's expected on first run.
  if ! nc -z -G 5 "$TARGET_IP" 22 2>/dev/null; then
    die "Cannot reach $TARGET_IP:22. Is Remote Login enabled on the target?"
  fi
  info "SSH reachable but not yet key-authenticated — ssh-copy-id will prompt for password."
fi

# ---------------------------------------------------------------- 2. Pubkey
if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$TARGET_HOST" "true" 2>/dev/null; then
  info "SSH pubkey already installed."
else
  info "Installing SSH pubkey (you'll be prompted for the target's password)..."
  ssh-copy-id "${SSH_OPTS[@]}" "$TARGET_HOST"
fi

# ---------------------------------------------------------------- 3. NOPASSWD sudo
if ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "sudo -n true" 2>/dev/null; then
  info "Passwordless sudo already active."
else
  info "Enabling passwordless sudo (you'll be prompted for the target's password one last time)..."
  ssh -t "${SSH_OPTS[@]}" "$TARGET_HOST" "
    echo '$TARGET_USER ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/nopasswd > /dev/null &&
    sudo chmod 440 /etc/sudoers.d/nopasswd
  "
fi

# ---------------------------------------------------------------- 4. Xcode CLT
info "Checking Xcode Command Line Tools..."
if ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "xcode-select -p" >/dev/null 2>&1; then
  info "CLT already installed."
else
  info "Installing Xcode Command Line Tools (this can take several minutes)..."
  # Well-known softwareupdate trick: touch the in-progress sentinel so
  # softwareupdate -l lists CLT without triggering the GUI dialog.
  if ! ssh "${SSH_OPTS[@]}" "$TARGET_HOST" '
    set -e
    sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    PROD=$(softwareupdate -l 2>/dev/null | awk "/\\* Label:.*Command Line Tools/ {sub(/^\\* Label: /, \"\"); print; exit}")
    if [ -z "$PROD" ]; then
      echo "Could not auto-detect CLT update label." >&2
      exit 1
    fi
    sudo softwareupdate -i "$PROD" --verbose
    sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  '; then
    warn "Automated CLT install failed. Falling back: run 'sudo xcode-select --install' on the target,"
    warn "click Install on the dialog, then re-run this script."
    exit 1
  fi
fi

# ---------------------------------------------------------------- 5. Auto-updates off
info "Disabling softwareupdate auto-schedule..."
ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "sudo softwareupdate --schedule off" >/dev/null

# ---------------------------------------------------------------- 6. Rsync repo
info "Rsyncing repo to $TARGET_HOST:~/mac-setup..."
rsync -az --delete \
  --exclude=.git --exclude=test/tmp --exclude=.DS_Store \
  -e "ssh ${SSH_OPTS[*]}" \
  "$REPO_ROOT/" "$TARGET_HOST:mac-setup/"

# ---------------------------------------------------------------- 7. Run bin/setup
info "Running bin/setup on target..."
# Pass setup args through ssh with proper shell quoting.
printf -v QUOTED ' %q' "${SETUP_ARGS[@]}"
ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "cd ~/mac-setup && ruby bin/setup --all${QUOTED}"

info "Done on the controller side."
info ""
info "Next: log into the target's desktop (GUI session), open Terminal, and run:"
info ""
info "    cd ~/mac-setup && ./install-ssh-target.sh"
info ""
info "That finalizes the default browser, SSH keychain, and Finder/Dock restart —"
info "the few things that need an active Aqua session."
