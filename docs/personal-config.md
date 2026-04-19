# Personal Config with `age` Encryption

Personal files (dotfiles, SSH config, git identity, tokens) are stored encrypted in the public repo as `config/personal.age`. At setup time, the **Secrets** module decrypts them into `config/personal/` (gitignored), where other modules read them.

One passphrase protects everything. No external service, no OS-specific keychain.

---

## How it works

```
config/personal.age    ← committed (encrypted, safe in public repo)
config/personal/       ← gitignored (decrypted at setup time)
├── git_identity.yml   ← read by GitConfig module
├── ssh_config         ← installed as ~/.ssh/config by Ssh module
└── ...                ← add more files as needed
```

The Secrets module runs right after Homebrew (which installs `age`) and before any module that reads personal config. Priority chain for values like git name/email:

1. `--git-name` / `--git-email` CLI flags (highest priority)
2. `config/personal/git_identity.yml`
3. Interactive prompt (lowest priority)

---

## Initial setup (one-time)

### 1. Harvest from your current Mac

Run on a Mac that's already configured the way you like:

```bash
cd ~/mac-setup
ruby bin/harvest
```

This collects dotfiles, git identity, SSH config, gh token, Claude Code config, macOS defaults, Brewfile, and keyboard remapping into `config/personal/`. Use `--force` to overwrite existing files.

Output:
```
config/personal/
├── dotfiles/          ← .zshrc, .vimrc, .tmux.conf, etc.
├── git_identity.yml   ← git name/email
├── ssh_config         ← ~/.ssh/config
├── known_hosts        ← ~/.ssh/known_hosts
├── gh_token           ← GitHub CLI token
├── claude/            ← Claude Code settings
├── macos_defaults_discovered.yml  ← for review, merge into config/macos_defaults.yml
├── Brewfile.discovered            ← for review, merge into config/Brewfile
└── keyboard_remapping.json        ← for review
```

### 2. Review and curate

The harvested files are a raw snapshot. Review before packing:

- **macos_defaults_discovered.yml** — cherry-pick entries into `config/macos_defaults.yml`
- **Brewfile.discovered** — cherry-pick entries into `config/Brewfile`
- **dotfiles/** — remove anything machine-specific (hardcoded paths, temp aliases)
- **gh_token** — verify this is the right token / account
- **keyboard_remapping.json** — if present, note the hidutil mappings for a future module

### 3. Add your own files

You can also add files manually. Some examples:

**Git identity** (`config/personal/git_identity.yml`):
```yaml
name: Jane Doe
email: jane@example.com
```

**SSH config** (`config/personal/ssh_config`):
```
Host github.com
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519

Host *
  ServerAliveInterval 60
```

Add any other dotfiles or config you want to carry between Macs.

### 4. Install age (if not already installed)

```bash
brew install age
```

### 5. Pack (encrypt)

```bash
cd ~/mac-setup
tar cz -C config/personal . | age -p > config/personal.age
```

`age -p` will prompt you to enter and confirm a passphrase. Choose something memorable — this is the **one passphrase** you need to remember.

### 6. Commit the encrypted file

```bash
git add config/personal.age
git commit -m "Add encrypted personal config"
```

`config/personal/` is in `.gitignore` — only the encrypted `.age` file is tracked.

---

## At setup time (on a new Mac)

### GUI mode

```bash
ruby bin/setup
# → Secrets module prompts: "Enter passphrase for config/personal.age: "
# → decrypts to config/personal/
# → subsequent modules read from it
```

### SSH mode

Preferred — pass via env var (not visible in `ps` output):

```bash
AGE_PASSPHRASE="your-passphrase" ./install-ssh-controller.sh <target-ip> \
  --hostname my-mac
```

Or via CLI flag (visible in `ps` briefly — use only when env var isn't practical):

```bash
./install-ssh-controller.sh <target-ip> \
  --hostname my-mac \
  --passphrase "your-passphrase"
```

Priority: `--passphrase` flag > `AGE_PASSPHRASE` env var > interactive prompt.

---

## Updating personal config

Re-harvest from your current Mac (overwrites):

```bash
ruby bin/harvest --force
```

Or edit files in `config/personal/` manually. Then re-encrypt:

```bash
# Re-encrypt
tar cz -C config/personal . | age -p > config/personal.age

# Commit
git add config/personal.age
git commit -m "Update personal config"
git push
```

---

## Re-decrypting (e.g., after a git pull)

If `config/personal/` is empty or missing:

```bash
age -d config/personal.age | tar xz -C config/personal/
```

Or just re-run the Secrets module:

```bash
ruby bin/setup secrets
```

---

## File reference

| File | Format | Read by |
|---|---|---|
| `dotfiles/.zshrc`, etc. | Shell config files | Shell module (planned — symlinking not yet implemented) |
| `git_identity.yml` | YAML: `name`, `email` | GitConfig module |
| `ssh_config` | Standard SSH config format | Ssh module (copied to `~/.ssh/config`) |
| `known_hosts` | SSH known hosts | Ssh module (planned — merge not yet implemented) |
| `gh_token` | Plain text, one line | GithubAuth module (planned) |
| `claude/settings.json` | JSON | ClaudeCode module (planned) |
| `macos_defaults_discovered.yml` | YAML | Manual review → merge into `config/macos_defaults.yml` |
| `Brewfile.discovered` | Brewfile format | Manual review → merge into `config/Brewfile` |
| `keyboard_remapping.json` | hidutil JSON | Manual review → future Keyboard module |

Files marked "planned" are harvested now but the modules that consume them are not yet implemented. The Secrets module just decrypts the tarball — individual modules decide what to read from `config/personal/`.

---

## Security notes

- The encrypted file is safe to commit to a public repo. `age` uses scrypt for passphrase-based key derivation — brute-force is impractical with a reasonable passphrase.
- The decrypted directory (`config/personal/`) is gitignored. It exists only on machines where the passphrase has been entered.
- The `--passphrase` CLI flag passes the value via process arguments, which are briefly visible in `ps` output. Prefer the `AGE_PASSPHRASE` env var (not visible in `ps`) or the interactive prompt (GUI mode) for better security.
- SSH private keys are NOT stored in `config/personal/` — they're generated fresh per machine by the Ssh module. Only the SSH *config* (host aliases, options) is shared.
