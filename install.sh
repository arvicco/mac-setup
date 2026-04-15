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
echo "==> Ready! Now run:"
echo ""
echo "    cd ~/mac-setup && ruby bin/setup"
echo ""
echo "    Options:"
echo "      ruby bin/setup --all    # run all modules without prompting"
echo "      ruby bin/setup --list   # list available modules"
echo ""
