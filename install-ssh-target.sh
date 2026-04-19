#!/bin/bash
# install-ssh-target.sh — final step of SSH-mode setup.
#
# Run this on the TARGET Mac, in a Terminal window, after you've logged in
# graphically. Handles the few things that require an active Aqua session
# and therefore couldn't run during the earlier SSH-driven phase:
#
#   - setting the default browser (LaunchServices needs a GUI session)
#   - ssh-add --apple-use-keychain (ssh-agent is bound to your login session)
#   - restarting Finder/Dock so they pick up the defaults written earlier
#
# Assumes install-ssh-controller.sh has already run successfully from the
# controller. Safe to re-run — every step is idempotent.

set -euo pipefail

info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!!  %s\033[0m\n' "$*" >&2; }

# 1. Default browser
if [ ! -x /opt/homebrew/bin/defaultbrowser ]; then
  warn "defaultbrowser not found. Skipping. (It should be installed via Brewfile.)"
elif [ ! -d "/Applications/Google Chrome.app" ]; then
  warn "Google Chrome.app not present in /Applications — skipping default-browser step."
else
  info "Setting Chrome as default browser..."
  /opt/homebrew/bin/defaultbrowser chrome \
    || warn "defaultbrowser returned non-zero. Chrome may need to be launched once before LaunchServices registers it."
fi

# 2. SSH keys to macOS keychain (general-purpose + dedicated GitHub)
for KEY in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519_github"; do
  if [ -f "$KEY" ]; then
    info "Adding $KEY to macOS keychain..."
    ssh-add --apple-use-keychain "$KEY"
  else
    warn "No SSH key at $KEY — skipping."
  fi
done

# 3. Restart Finder and Dock so they pick up defaults applied earlier
info "Restarting Finder and Dock..."
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true

info "Done. Your Mac is fully set up."
