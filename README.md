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

### Harvesting config from an existing Mac

On a Mac that's already set up the way you like:

```bash
ruby bin/harvest          # collects dotfiles, git id, tokens, defaults, etc.
ruby bin/harvest --force  # overwrite existing config/personal/ files
```

Review `config/personal/`, then pack and commit — see [docs/personal-config.md](docs/personal-config.md).

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
  --git-email jane@example.com \
  --passphrase "your-age-passphrase"
```

## Setup Steps (in execution order)

1. **Hostname** — Prompts for a machine name and sets HostName, ComputerName, and LocalHostName via `scutil`
2. **Homebrew** — Installs Homebrew (if missing) and all packages from `config/Brewfile`
3. **Secrets** — Decrypts `config/personal.age` → `config/personal/` using `age`. Skips if no `.age` file or already decrypted.
4. **Node** — Installs nvm and Node.js LTS
5. **Claude Code** — Verifies Claude Code CLI was installed via Brewfile (`cask "claude-code"`)
6. **Cask** — Post-install configuration for Homebrew Cask apps
7. **macOS Defaults** — Applies system preferences from `config/macos_defaults.yml` (Finder, Dock, etc.)
8. **Auto Login** — Enables boot-time auto-login for the user listed in `config/personal/autologin.yml` (home-server pattern: machine comes up unattended after a power outage). Skipped if no config file present.
9. **Power Management** — Disables low power mode, prevents auto-sleep on AC/battery, enables auto-restart after power failure, and wake-on-LAN (magic packet)
10. **Security** — Enables macOS firewall
11. **Karabiner** — Installs Karabiner-Elements config (`config/karabiner.json`): F6 → Lock Screen, Shift+Return → ESC+Return in terminal emulators (newline for Claude Code and other TUI apps)
12. **Keyboard Layouts** — Installs any `.bundle` from `config/keyboard_layouts/` to `~/Library/Keyboard Layouts/` (e.g. `DvorakExt.bundle` — Dvorak-QWERTY-⌘ with Opt+letter mappings for č š ž đ è à and ESC+Return on Shift+Return)
13. **Keyboard Shortcuts** — Writes `config/keyboard_shortcuts.yml` to `com.apple.symbolichotkeys` (disable Spotlight Cmd+Space, rebind Cmd+Space to "Select previous input source", disable Accessibility zoom/contrast/invert shortcuts)
14. **Git Config** — Sets global git configuration (name, email, default branch, editor). Reads from `config/personal/git_identity.yml` when present.
15. **Shell** — Installs Oh My Zsh (if missing) and **copies** every file in `config/personal/dotfiles/` into `~/` (existing targets → backed up to `.bak-<timestamp>`). Copies (not symlinks) so the dotfiles survive removing the mac-setup checkout after bootstrap.
16. **iTerm2** — Copies `config/personal/iterm2.plist` to `~/Library/Preferences/com.googlecode.iterm2.plist`. Skipped if iTerm2 is running (it caches prefs in memory and would overwrite on quit).
17. **SSH** — Generates two ed25519 keys: `~/.ssh/id_ed25519` (general-purpose) and `~/.ssh/id_ed25519_github` (dedicated). Installs `~/.ssh/config` from `config/personal/ssh_config` when present — use `Host github.com / IdentityFile ~/.ssh/id_ed25519_github / IdentitiesOnly yes` to pin the GitHub-only key. Both keys are added to the macOS keychain when a GUI SSH agent is reachable.
18. **GitHub Auth** — Reads `config/personal/gh_token`, runs `gh auth login --with-token` (skip if already authed), then uploads `~/.ssh/id_ed25519_github.pub` via `gh ssh-key add` titled `mac-setup: <hostname>` (skip if GitHub already has that key body).
19. **Rclone** — Copies `config/personal/rclone.conf` to `~/.config/rclone/rclone.conf` with `0600` permissions (the file holds OAuth tokens for cloud remotes).
20. **Tailscale** — Joins this Mac to your tailnet. Reads `config/personal/tailscale.yml` (OAuth client creds + tags), installs `tailscaled` as a system daemon (headless, survives reboots), mints a short-lived single-use auth key via the Tailscale API, runs `tailscale up --ssh --accept-dns`.

## Manual steps after setup

Some macOS security restrictions require manual interaction — these can't be scripted. Complete them once after the setup finishes.

**Permissions (required for installed tools to work):**
- [ ] **Karabiner-Elements** — open the app, then grant permissions in System Settings → Privacy & Security:
  - Input Monitoring → enable karabiner_grabber and karabiner_observer
  - Accessibility → enable karabiner_grabber
  - Allow the system extension when macOS prompts

**One-time Tailscale admin setup (before first Tailscale run):**
- [ ] Create an OAuth client at https://login.tailscale.com/admin/settings/oauth with scope `auth_keys` (write). Save the client ID + secret into `config/personal/tailscale.yml`.
- [ ] Define a tag in your ACL policy with yourself as a `tagOwner`, e.g.:
  ```json
  "tagOwners": { "tag:home-server": ["autogroup:admin"] }
  ```
  Reference it from `tailscale.yml` (`tags: [tag:home-server]`). OAuth-minted keys must be tagged.

**GUI-only steps (SSH mode — run `install-ssh-target.sh`, or do manually):**
- [ ] **Default browser** — run `defaultbrowser chrome` or set in System Settings → Desktop & Dock
- [ ] **SSH keychain** — run `ssh-add --apple-use-keychain ~/.ssh/id_ed25519 && ssh-add --apple-use-keychain ~/.ssh/id_ed25519_github`
- [ ] **Finder/Dock restart** — log out and back in, or run `killall Finder; killall Dock`
- [ ] **Activate custom keyboard layout** — System Settings → Keyboard → Input Sources → `+` → English → pick `Dvorak Plus`. This one GUI click writes the entry into `com.apple.inputsources` (TCC-protected — can't be scripted). After this step, mac-setup re-runs will detect the layout there and leave the HIToolbox bookkeeping alone (adding it in both places duplicates the entry in the menu). A logout or reboot may be needed for the layout to first appear after the bundle is installed.

**Not automatable at all:**
- [ ] **iPhone Widgets** — disable in System Settings → Desktop & Dock → Widgets (no known `defaults write` key)
- [ ] **Require password after screen lock** — set to "After 1 hour" in System Settings → Lock Screen (the `com.apple.screensaver askForPasswordDelay` key has been SIP-protected since Catalina and only accepts changes through the GUI auth dialog)
- [ ] **Location Services** — disable in System Settings → Privacy & Security → Location Services (TCC-protected since Catalina; the underlying `/var/db/locationd` plist silently rejects `defaults write`)
- [ ] **FileVault** — leave **off** (default). Server/always-on use case: enabling FileVault blocks unattended reboot after a power outage because the disk stays locked until someone types the password. Apple Silicon still encrypts the SSD at rest with FileVault off.
- [ ] **Allow accessories to connect** — set to "Always" in System Settings → Privacy & Security (Apple Silicon hardware-security feature, Secure Enclave-gated; only MDM config profiles can set it non-interactively)
- [ ] **Keyboard → Adjust keyboard brightness in low light** — turn off in System Settings → Keyboard (controlled by ambient-light sensor → SMC; no user-level `defaults` key exists)
- [ ] **Keyboard → Keyboard brightness** — set to minimum via the brightness-down key (backlight level is hardware-controlled, not scriptable; with auto-adjust off, the minimum setting will persist)
- [ ] **iCloud / Apple ID** sign-in
- [ ] **Browser profile** sign-in
- [ ] **App-specific permissions** (screen recording, camera, etc.) — granted on first use

## Customization

- **Packages:** Edit `config/Brewfile`
- **macOS preferences:** Edit `config/macos_defaults.yml`
- **Personal config (git identity, SSH config, etc.):** See [docs/personal-config.md](docs/personal-config.md)
- **Git:** Edit values in `lib/mac_setup/git_config.rb` or `config/personal/git_identity.yml`
- **New modules:** Create a class inheriting `MacSetup::BaseModule` in `lib/mac_setup/`

## Further docs

- [docs/personal-config.md](docs/personal-config.md) — how to pack/unpack personal config (dotfiles, SSH config, tokens) with `age` encryption
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
