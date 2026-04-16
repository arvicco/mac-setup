# Running mac-setup on a Target Mac

Two supported modes. Both end at the same state; they differ in where you sit and what you prepare beforehand.

| | GUI mode (local) | SSH mode (remote) |
|---|---|---|
| Where you run the script | On the target Mac itself | From a controller Mac, over SSH |
| Bootstrap script | `install-gui.sh` | `install-ssh-controller.sh` + `install-ssh-target.sh` |
| Prerequisites on target | Fresh Mac, first-boot wizard done | Same + Remote Login enabled |
| Interactive prompts | Works naturally | Pass values via flags instead |
| GUI dialogs during install | Clickable | Hang invisibly — bootstrap preempts them |
| Works for Mac #1 (no controller) | ✅ | ❌ |
| Parallel work on controller | ❌ | ✅ |
| Matches `rake test:vm` | ❌ | ✅ |

**Pick GUI mode** for your very first Mac, for offline installs, or one-shots where you don't mind babysitting. **Pick SSH mode** for everything else — it's the same path our VM tests exercise, so anything that passes in CI passes on a real Mac.

---

## GUI mode

On a freshly-unboxed Mac, after the first-boot wizard.

### One-liner (fetches and runs `install-gui.sh`)

```bash
curl -fsSL https://raw.githubusercontent.com/arvicco/mac-setup/main/install-gui.sh | bash
```

`install-gui.sh` installs Xcode Command Line Tools, clones the repo to `~/mac-setup`, then runs `ruby bin/setup`. You'll be prompted to pick modules, enter a hostname, and enter git identity. GUI dialogs (CLT install, Gatekeeper) appear and you click through.

### Manual

```bash
git clone https://github.com/arvicco/mac-setup.git ~/mac-setup
cd ~/mac-setup
ruby bin/setup              # interactive
# or
ruby bin/setup --all        # run all modules
```

### Non-interactive local run

Same flags as SSH mode work here, if you want to avoid the prompts:

```bash
ruby bin/setup --all \
  --hostname my-mac \
  --git-name "Jane Doe" \
  --git-email jane@example.com
```

---

## SSH mode

Two scripts: one runs on the controller to do the bulk of the work, one runs on the target at the end to finalize GUI-only bits.

### Irreducible manual step (target)

Right after the first-boot wizard:

1. Finish macOS first-boot wizard — create the `admin` user
2. System Settings → General → Sharing → turn on **Remote Login**

Everything else is scripted.

### Controller-side: `install-ssh-controller.sh`

From your controller Mac (with this repo checked out):

```bash
cd ~/mac-setup
./install-ssh-controller.sh <target-ip> \
  --hostname my-new-mac \
  --git-name "Jane Doe" \
  --git-email jane@example.com
```

The script:

1. Verifies SSH access on port 22
2. Installs your pubkey (`ssh-copy-id`) — prompts for the target's admin password once
3. Enables NOPASSWD sudo via `/etc/sudoers.d/nopasswd`
4. Installs Xcode Command Line Tools using the `softwareupdate` sentinel-file trick — **no GUI dialog needed**. Falls back with a clear error if the trick stops working on a future macOS release.
5. Disables `softwareupdate` auto-schedule so no update fires mid-`brew bundle`
6. Rsyncs the current working copy of the repo (local WIP changes get tested, not `main`) to `~admin/mac-setup/` on the target
7. Runs `ruby bin/setup --all <your-flags>` over SSH with output streaming back

Any args after the IP are forwarded to `bin/setup`. Always pass `--hostname`, `--git-name`, `--git-email` — without them the prompts will hang on an SSH session with no TTY.

Safe to re-run. Every step is idempotent.

#### Logging

Tee output to a file on the controller:

```bash
./install-ssh-controller.sh 192.168.1.50 --hostname my-mac … 2>&1 \
  | tee setup-$(date +%F).log
```

### Target-side: `install-ssh-target.sh`

After the controller script finishes, log into the target Mac graphically (at the console or via Screen Sharing), open Terminal, and run:

```bash
cd ~/mac-setup && ./install-ssh-target.sh
```

This handles the three things that need an active Aqua session:

1. `defaultbrowser chrome` — set Chrome as default browser (LaunchServices needs a GUI session)
2. `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` — add SSH key to macOS keychain (ssh-agent is bound to login session)
3. `killall Finder; killall Dock` — restart so they pick up the defaults applied earlier

Safe to re-run.

### Why two scripts

A handful of macOS operations require the user's active GUI session and can't be triggered remotely:

| Step | Why it can't run over SSH |
|---|---|
| `defaultbrowser` / LaunchServices | Needs an Aqua session to register the browser |
| `ssh-add --apple-use-keychain` | ssh-agent is launched per GUI login, not per SSH session |
| `killall Finder/Dock` | No such processes exist in a pure SSH context |
| Any Gatekeeper/Privacy/Notification prompt | Hangs invisibly without a GUI to click through |

`install-ssh-controller.sh` deliberately stops short of these, so it never hangs. `install-ssh-target.sh` picks them up once you're in front of the target.

### Things the script deliberately leaves to you

After both scripts run, the target still needs manual attention for:

- iCloud / Apple ID sign-in (security-sensitive, not scriptable safely)
- Browser profile sign-in
- Granting accessibility / screen recording permissions to any installed casks
- Anything in System Settings that requires your consent

---

## Testing changes before running on a real Mac

`rake test:vm` clones a Tart VM and runs `install-ssh-controller.sh`'s core flow against it. Same SSH path as the real run, so anything that passes there will pass on a real Mac.

See [tart-vm-setup.md](tart-vm-setup.md) for one-time Tart base VM setup.

```bash
rake test:vm                       # full run, auto-teardown
MAC_SETUP_VM_KEEP=1 rake test:vm   # leave clone running to poke around
```

---

## Quick reference

**GUI mode — first Mac / local run (on the target):**
```bash
curl -fsSL https://raw.githubusercontent.com/arvicco/mac-setup/main/install-gui.sh | bash
```

**SSH mode — from controller (after Remote Login enabled on target):**
```bash
cd ~/mac-setup
./install-ssh-controller.sh <target-ip> \
  --hostname my-mac \
  --git-name "Jane Doe" \
  --git-email jane@example.com
```

Then on the target's Terminal after GUI login:
```bash
cd ~/mac-setup && ./install-ssh-target.sh
```
