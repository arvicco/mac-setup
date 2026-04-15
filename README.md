# mac-setup

Automated MacBook setup script. Configures a fresh Mac with my standard tools, apps, and preferences.

## Quick Start

On a fresh Mac, run:

```bash
curl -fsSL https://raw.githubusercontent.com/vb/mac-setup/main/install.sh | bash
```

This will:
1. Install Xcode Command Line Tools
2. Clone this repo to `~/mac-setup`
3. Run the setup script

## Manual Usage

```bash
git clone https://github.com/vb/mac-setup.git ~/mac-setup
cd ~/mac-setup
ruby bin/setup
```

### Options

```
ruby bin/setup            # Interactive — prompts for each module
ruby bin/setup --all      # Run all modules
ruby bin/setup --list     # List available modules
ruby bin/setup homebrew   # Run specific module(s) by name
```

## Modules

| Module | Description |
|--------|-------------|
| Homebrew | Installs Homebrew and packages from `config/Brewfile` |
| Cask | Post-install configuration for Cask apps |
| Macos Defaults | Applies macOS system preferences |
| Git Config | Sets global git configuration |
| Shell | Zsh and Oh My Zsh setup |
| Ssh | Generates SSH keys |
| Node | Installs nvm and Node.js LTS |

## Customization

- **Packages:** Edit `config/Brewfile`
- **macOS preferences:** Edit `config/macos_defaults.yml`
- **Git:** Edit values in `lib/mac_setup/git_config.rb`
- **New modules:** Create a class inheriting `MacSetup::BaseModule` in `lib/mac_setup/`

## Testing

```bash
rake test:unit
```

## Requirements

- macOS (ships with Ruby 2.6+)
- No external gems required
