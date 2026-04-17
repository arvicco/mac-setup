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

### 1. Install age

```bash
brew install age
```

### 2. Create your personal config directory

```bash
mkdir -p config/personal
```

### 3. Add your files

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

### 4. Pack (encrypt)

```bash
cd ~/mac-setup
tar cz -C config/personal . | age -p > config/personal.age
```

`age -p` will prompt you to enter and confirm a passphrase. Choose something memorable — this is the **one passphrase** you need to remember.

### 5. Commit the encrypted file

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

After changing files in `config/personal/`:

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
| `git_identity.yml` | YAML: `name`, `email` | GitConfig module |
| `ssh_config` | Standard SSH config format | Ssh module (copied to `~/.ssh/config`) |

Add more files as you add modules that need personal config. The Secrets module just decrypts the tarball — individual modules decide what to read from `config/personal/`.

---

## Security notes

- The encrypted file is safe to commit to a public repo. `age` uses scrypt for passphrase-based key derivation — brute-force is impractical with a reasonable passphrase.
- The decrypted directory (`config/personal/`) is gitignored. It exists only on machines where the passphrase has been entered.
- The `--passphrase` CLI flag passes the value via process arguments, which are briefly visible in `ps` output. Prefer the `AGE_PASSPHRASE` env var (not visible in `ps`) or the interactive prompt (GUI mode) for better security.
- SSH private keys are NOT stored in `config/personal/` — they're generated fresh per machine by the Ssh module. Only the SSH *config* (host aliases, options) is shared.
