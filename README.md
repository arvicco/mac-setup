# mac-setup

Automated MacBook setup script. Configures a fresh Mac with my standard tools, apps, and preferences.

## Quick Start

Two supported modes — pick based on whether you're sitting at the target or at a controller Mac. See [docs/remote-setup.md](docs/remote-setup.md) for the full comparison.

### GUI mode — run on the target Mac

```bash
curl -fsSL https://raw.githubusercontent.com/arvicco/mac-setup/main/install-gui.sh | bash
```

`install-gui.sh` installs Xcode CLT, clones the repo to `~/mac-setup`, then runs `ruby bin/setup`.

### SSH mode — run from a controller Mac

On the target: finish first-boot wizard, enable Remote Login (System Settings → General → Sharing).

From the controller:

```bash
cd ~/mac-setup
./install-ssh-controller.sh <target-ip> \
  --hostname my-new-mac \
  --git-name "Jane Doe" \
  --git-email jane@example.com
```

`install-ssh-controller.sh` handles everything else: SSH pubkey, NOPASSWD sudo, Xcode CLT (headless), `softwareupdate --schedule off`, rsync of the repo, and a non-interactive `ruby bin/setup --all` run.

Then log into the target's desktop and run:

```bash
cd ~/mac-setup && ./install-ssh-target.sh
```

to finalize the few GUI-only steps (default browser, SSH keychain, Finder/Dock restart).

## Manual Usage

```bash
git clone https://github.com/arvicco/mac-setup.git ~/mac-setup
cd ~/mac-setup
ruby bin/setup
```

### Options

```
ruby bin/setup            # Interactive — prompts for each module
ruby bin/setup --all      # Run all modules
ruby bin/setup --list     # List available modules
ruby bin/setup homebrew   # Run specific module(s) by name

# Non-interactive: provide values up front so prompts are skipped.
# Missing flags fall back to the usual prompts.
ruby bin/setup --all \
  --hostname my-mac \
  --git-name "Jane Doe" \
  --git-email jane@example.com
```

## Setup Steps (in execution order)

1. **Hostname** — Prompts for a machine name and sets HostName, ComputerName, and LocalHostName via `scutil`
2. **Homebrew** — Installs Homebrew (if missing) and all packages from `config/Brewfile`
3. **Node** — Installs nvm and Node.js LTS
4. **Claude Code** — Installs Claude Code CLI via npm (`@anthropic-ai/claude-code`)
5. **Cask** — Post-install configuration for Homebrew Cask apps
6. **macOS Defaults** — Applies system preferences from `config/macos_defaults.yml` (Finder, Dock, etc.)
7. **Terminal App** — Binds Shift+Return to newline in Apple Terminal.app's active profile (skipped if Terminal.app is running)
8. **Git Config** — Sets global git configuration (name, email, default branch, editor)
9. **Shell** — Installs Oh My Zsh (if missing) and configures zsh
10. **SSH** — Generates an ed25519 SSH key (if missing) and adds it to the macOS keychain

## Customization

- **Packages:** Edit `config/Brewfile`
- **macOS preferences:** Edit `config/macos_defaults.yml`
- **Git:** Edit values in `lib/mac_setup/git_config.rb`
- **New modules:** Create a class inheriting `MacSetup::BaseModule` in `lib/mac_setup/`

## Further docs

- [docs/remote-setup.md](docs/remote-setup.md) — running the script in GUI mode (on the target) vs. SSH mode (from a controller), with target-Mac prep for each
- [docs/tart-vm-setup.md](docs/tart-vm-setup.md) — one-time Tart base VM setup used by `rake test:vm`

## Testing

```bash
rake test:unit   # unit tests
rake test:vm     # end-to-end run inside a cloned Tart VM (see docs/tart-vm-setup.md)
```

## Requirements

- macOS (ships with Ruby 2.6+)
- No external gems required
