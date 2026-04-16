# Tart VM Setup for `rake test:vm`

End-to-end guide for building a reusable Tahoe base VM under [Tart](https://tart.run), used by `rake test:vm` to test `mac-setup` on a clean macOS install. You clone this base for every test run; the base itself stays pristine.

Apple's license caps you at 2 concurrent macOS guest VMs per host. Fine for our workflow.

---

## 1. One-time host setup

### Install Tart

```bash
brew install cirruslabs/cli/tart
```

### Shorten DHCP lease time (important)

macOS's built-in DHCP server (used by Tart's default NAT networking) hands out 1-hour leases from a pool of 253 addresses. Cloning and destroying many short-lived VMs exhausts the pool. Drop the lease to 10 minutes:

```bash
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.InternetSharing.default.plist bootpd -dict DHCPLeaseTimeSecs -int 600
```

Takes effect on next `bootpd` restart (next VM boot or host reboot). Reversible with `sudo defaults delete ...`.

Reference: <https://tart.run/faq/#changing-the-default-dhcp-lease-time>

---

## 2. Create the base VM

Downloads the latest Tahoe IPSW (~20 GB) and boots it. Takes a while; let it finish.

```bash
tart create --from-ipsw=latest tahoe-base
tart run tahoe-base
```

**Snag: the VM window opens in the background.** Terminal stays attached and looks hung. Check `Cmd-Tab` / Mission Control for a window named `tahoe-base`. Terminal output is always quiet during VM run — the window is the interface.

First boot from fresh IPSW can take 10-20 minutes with no visible progress. Have patience before assuming something is broken. `ps aux | grep tart` confirms the process is alive.

---

## 3. macOS first-boot wizard (inside the VM)

Complete the first-boot wizard with automation-friendly choices:

- Language, region — as you like
- **Skip Apple ID / iCloud** — not needed, faster
- **Skip Siri, Screen Time, analytics, Touch ID** — reduces first-run noise and hardware dependencies
- **Create admin user:**
  - Short name: `admin` (matches Tart tooling conventions)
  - Password: whatever you want; you'll enter it once, then enable passwordless sudo below
- **FileVault: Off** (the wizard may offer it; pick "Set up later" / "Turn off")
  - Reason: FileVault adds a pre-boot password prompt that hangs headless VMs. The VM's disk image is protected at rest by your host's FileVault anyway.
  - Verify after boot: `fdesetup status` → should say "FileVault is Off."

Once at the desktop, open Terminal.app inside the VM.

---

## 4. Inside-VM preparation

### Enable Remote Login (SSH)

System Settings → General → Sharing → turn on **Remote Login**.

### Install SSH pubkey (from host)

Clipboard sharing between host and macOS guest is **not supported** under Virtualization.framework — don't waste time copy-pasting. Use `ssh-copy-id` from the host instead (password SSH is on by default on fresh macOS):

```bash
# on the host
tart ip tahoe-base                # note the guest IP, e.g. 192.168.64.2
ssh-copy-id admin@<that-ip>       # enter admin password once
```

Verify key auth works:

```bash
ssh admin@<that-ip> "whoami"      # should print "admin" with no prompt
```

### Enable passwordless sudo

Our `bin/setup` calls `sudo -v`, which hangs forever on a password prompt over SSH. Inside the VM (or via SSH once key auth works):

```bash
echo "admin ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/nopasswd
sudo chmod 440 /etc/sudoers.d/nopasswd
```

Enter the admin password once (last time).

**Snag:** if `sudo -l` still prompts for a password afterward, the file didn't land. Verify:

```bash
ls -l /etc/sudoers.d/          # should show "nopasswd" owned by root:wheel
sudo cat /etc/sudoers.d/nopasswd
```

If empty, re-run the `tee` command. If ownership is wrong, `sudo chown root:wheel /etc/sudoers.d/nopasswd` — sudoers.d files must be root-owned or sudo silently ignores them.

Test from the host:

```bash
ssh admin@<that-ip> "sudo -n true && echo OK"   # should print OK
```

### Install Xcode Command Line Tools

Homebrew's installer triggers a **GUI dialog** to install CLT when it's missing. In our headless `--no-graphics` clones, that dialog sits invisible and hangs the test forever. Pre-install CLT now:

```bash
sudo xcode-select --install
```

Click **Install** on the dialog that appears in the VM window. Wait for it to finish (few minutes).

**Do not run `sudo xcodebuild -license accept`** — that's for full Xcode.app and errors out with "requires Xcode" if you only have CLT. The CLT license is accepted automatically by its installer.

### Apply pending macOS updates, disable auto-schedule

Prevents a background update from firing mid-test.

```bash
sudo softwareupdate --all --install --force
sudo softwareupdate --schedule off
```

### Disable display sleep

Paranoia — cleaner than debugging a screensaver-locked clone.

```bash
sudo pmset -a sleep 0 displaysleep 0
```

### Final sanity check from the host

```bash
ssh admin@<that-ip> "sudo -n true && echo OK && fdesetup status && xcode-select -p"
```

Expect:
```
OK
FileVault is Off.
/Library/Developer/CommandLineTools
```

---

## 5. Clean shutdown and snapshot

Tart has no explicit `snapshot` command — the base VM itself is the snapshot. Treat `tahoe-base` as read-only from this point forward.

```bash
# inside the VM
sudo shutdown -h now
```

**Do not use `tart stop`.** That force-kills the VM; let macOS flush cleanly so subsequent clones boot fast and don't log recovery messages.

---

## 6. Using the base VM

### With `rake test:vm`

Our rake task clones `tahoe-base` → boots the clone → rsyncs the repo → runs `bin/setup` → deletes the clone on exit.

```bash
rake test:vm                             # default run
MAC_SETUP_VM_KEEP=1 rake test:vm         # leave clone alive for inspection
MAC_SETUP_BASE_VM=other-vm rake test:vm  # use a different base
```

See `tasks/vm.rake` for details.

### Manual clone

```bash
tart clone tahoe-base scratch
tart run --no-graphics scratch &          # headless
tart ip scratch
ssh admin@<that-ip>
# ... work ...
tart stop scratch
tart delete scratch
```

---

## 7. Updating the base

When you need to update the template (new macOS version, change pubkey, etc.):

```bash
tart run tahoe-base         # boot interactively
# ... make changes inside ...
sudo shutdown -h now        # clean shutdown
```

If the update is destructive or you want rollback, `tart clone tahoe-base tahoe-base-backup` first.

---

## Common snags — quick reference

| Symptom | Cause | Fix |
|---|---|---|
| `tart run` looks hung, no output | VM window opened in background | Check `Cmd-Tab` / Mission Control |
| Clones fail to get IP after many runs | DHCP lease pool exhausted | One-time: drop lease to 600s (step 1) |
| Host clipboard won't paste into VM | Not supported for macOS guests | Use `ssh-copy-id`, not manual paste |
| `sudo -n true` returns "password required" | `/etc/sudoers.d/nopasswd` missing or wrong owner | Recreate file; ensure `root:wheel` ownership |
| `rake test:vm` hangs during Homebrew install | CLT dialog invisible in headless mode | Pre-install CLT in base VM |
| `xcodebuild -license accept` errors | Full Xcode not installed | Skip — CLT license is auto-accepted |
| macOS update kicks in mid-test | Auto-schedule enabled | `softwareupdate --schedule off` in base |
| Clones stuck at pre-boot password screen | FileVault enabled in guest | `sudo fdesetup disable`, wait for decryption, reshutdown |

---

## Teardown

```bash
tart stop tahoe-base 2>/dev/null
tart delete tahoe-base
```

Frees the ~50 GB base image from `~/.tart/vms/`.
