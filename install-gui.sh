#!/bin/bash
set -e

REPO_URL="https://github.com/arvicco/mac-setup.git"
INSTALL_DIR="$HOME/mac-setup"

echo "==> Mac Setup Bootstrap"
echo ""

# 1. Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
  echo "==> Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "    Waiting for installation to complete..."
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
  echo "    Done."
else
  echo "==> Xcode Command Line Tools already installed."
fi

# 2. Clone the repo
if [ -d "$INSTALL_DIR" ]; then
  echo "==> Updating existing mac-setup..."
  cd "$INSTALL_DIR"
  git pull origin main
else
  echo "==> Cloning mac-setup..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 3. Done — print next steps
echo ""
echo "==> Ready! Now run (edit the placeholders first):"
echo ""
echo "    cd ~/mac-setup"
echo "    ruby bin/setup --all --hostname new-box-name --git-name \"Your Name\" --git-email you@example.com --cleanup-secrets"
echo ""
echo "    Add --autologin if this is a server (boot-time auto-login)."
echo "    Full flag list: ruby bin/setup --help"
echo ""
