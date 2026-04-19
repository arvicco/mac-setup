# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"

# End-to-end test: clone a Tart VM, rsync this repo in, run bin/setup.
#
# Prerequisites (one-time):
#   1. Install Tart:  brew install cirruslabs/cli/tart
#   2. Build a base Tahoe VM named "tahoe-base" (configurable via env):
#        tart create --from-ipsw=latest tahoe-base
#        tart run tahoe-base
#      Then inside the guest:
#        - finish macOS first-boot (create "admin" user, any password)
#        - enable Remote Login (System Settings -> Sharing -> Remote Login)
#        - append your host's ~/.ssh/id_ed25519.pub to ~admin/.ssh/authorized_keys
#        - ensure `admin` has passwordless sudo (default on Tart images)
#        - shut down the guest cleanly
#   3. Snapshot-by-clone is implicit: we clone this base for each test run.
#
# Usage:
#   rake test:vm                       # run the safe-to-automate modules
#   MAC_SETUP_BASE_VM=my-vm rake test:vm
#   MAC_SETUP_VM_KEEP=1 rake test:vm   # leave the clone around for inspection

namespace :test do
  desc "Clone a Tart VM, rsync the repo, run bin/setup, tear down"
  task :vm do
    VMTest.new.run
  end
end

class VMTest
  BASE_VM      = ENV.fetch("MAC_SETUP_BASE_VM", "tahoe-base")
  CLONE_NAME   = ENV.fetch("MAC_SETUP_CLONE", "mac-setup-test-#{Process.pid}")
  SSH_USER     = ENV.fetch("MAC_SETUP_VM_USER", "admin")
  SSH_KEY      = ENV["MAC_SETUP_SSH_KEY"] # optional: pass -i path to ssh
  KEEP_ON_EXIT = ENV["MAC_SETUP_VM_KEEP"] == "1"

  # Values passed to the script's non-interactive flags. Override per run
  # via env if you want to see a specific hostname/identity in the VM.
  TEST_HOSTNAME   = ENV.fetch("MAC_SETUP_TEST_HOSTNAME", "mac-setup-test")
  TEST_GIT_NAME   = ENV.fetch("MAC_SETUP_TEST_GIT_NAME", "Mac Setup Test")
  TEST_GIT_EMAIL  = ENV.fetch("MAC_SETUP_TEST_GIT_EMAIL", "test@example.com")
  TEST_PASSPHRASE = ENV.fetch("MAC_SETUP_TEST_PASSPHRASE", "test-passphrase")
  TEST_FIXTURE    = File.join(File.expand_path("..", __dir__), "test", "fixtures", "personal.age")

  REPO_ROOT    = File.expand_path("..", __dir__)
  GUEST_REPO   = "/Users/#{SSH_USER}/mac-setup"

  def run
    check_prereqs!
    clone_vm
    install_cleanup_hook
    boot_vm
    ip = wait_for_ip
    wait_for_ssh(ip)
    rsync_repo(ip)
    install_test_secrets(ip)
    run_setup(ip)
    verify_setup(ip)
    verify_keyboard_layouts_dedup(ip)
    log "✓ Setup completed and verified in VM (ip=#{ip})"
  end

  private

  def log(msg)
    puts "[vm-test] #{msg}"
  end

  def sh!(*cmd)
    log "$ #{cmd.join(' ')}"
    system(*cmd) or abort "[vm-test] Command failed: #{cmd.join(' ')}"
  end

  def check_prereqs!
    abort "[vm-test] tart not found. brew install cirruslabs/cli/tart" unless system("command -v tart > /dev/null")
    out, _, status = Open3.capture3("tart", "list", "--format", "json")
    abort "[vm-test] tart list failed" unless status.success?
    vms = JSON.parse(out)
    abort "[vm-test] base VM '#{BASE_VM}' not found. See tasks/vm.rake header." unless vms.any? { |vm| vm["Name"] == BASE_VM }
  end

  def clone_vm
    log "Cloning #{BASE_VM} -> #{CLONE_NAME}"
    sh!("tart", "clone", BASE_VM, CLONE_NAME)
  end

  def boot_vm
    log "Booting #{CLONE_NAME} (headless, background)"
    @vm_pid = spawn("tart", "run", "--no-graphics", CLONE_NAME, out: "/tmp/#{CLONE_NAME}.log", err: [:child, :out])
    Process.detach(@vm_pid)
  end

  def wait_for_ip(timeout: 120)
    log "Waiting for VM IP..."
    deadline = Time.now + timeout
    loop do
      out, _, status = Open3.capture3("tart", "ip", CLONE_NAME)
      return out.strip if status.success? && !out.strip.empty?
      abort "[vm-test] Timed out waiting for IP" if Time.now > deadline
      sleep 2
    end
  end

  def wait_for_ssh(ip, timeout: 120)
    log "Waiting for SSH on #{ip}..."
    deadline = Time.now + timeout
    until system(*ssh_cmd(ip, "true"), out: File::NULL, err: File::NULL)
      abort "[vm-test] Timed out waiting for SSH" if Time.now > deadline
      sleep 3
    end
  end

  def rsync_repo(ip)
    log "Rsyncing repo to #{ip}:#{GUEST_REPO}"
    rsh = ssh_cmd_string
    sh!(
      "rsync", "-az", "--delete",
      "--exclude=.git", "--exclude=test/tmp", "--exclude=.DS_Store",
      "--exclude=config/personal",
      "-e", rsh,
      "#{REPO_ROOT}/", "#{SSH_USER}@#{ip}:#{GUEST_REPO}/"
    )
  end

  def install_test_secrets(ip)
    if File.exist?(TEST_FIXTURE)
      log "Copying test secrets fixture to guest config/personal.age"
      sh!(
        "scp", *ssh_opts,
        TEST_FIXTURE, "#{SSH_USER}@#{ip}:#{GUEST_REPO}/config/personal.age"
      )
    else
      log "No test fixture at #{TEST_FIXTURE} — Secrets module will skip."
    end
  end

  # Modules we run in the VM. Excluded because they can't work or be verified
  # in a headless Tart VM:
  #   - cask: `defaultbrowser chrome` requires LaunchServices to see Chrome,
  #     which it doesn't in a headless session
  #   - powermanagement: pmset silently drops settings on hardware without a
  #     detectable power source, with no way to read back what was set
  VM_MODULES = %w[
    hostname homebrew secrets node claudecode
    macosdefaults security karabiner
    keyboardlayouts keyboardshortcuts gitconfig shell ssh
  ].freeze

  def run_setup(ip)
    setup_args = [
      *VM_MODULES,
      "--hostname", TEST_HOSTNAME,
      "--git-name", TEST_GIT_NAME,
      "--git-email", TEST_GIT_EMAIL,
      "--passphrase", TEST_PASSPHRASE
    ]
    log "Running bin/setup #{Shellwords.join(setup_args)}"
    remote = "cd #{Shellwords.escape(GUEST_REPO)} && ruby bin/setup #{Shellwords.join(setup_args)}"
    sh!(*ssh_cmd(ip, remote))
  end

  def verify_setup(ip)
    log "Verifying setup..."
    checks = {
      # Hostname
      "scutil --get ComputerName" => TEST_HOSTNAME,
      # macOS defaults — spot-check representative entries
      "defaults read NSGlobalDomain AppleInterfaceStyle" => "Dark",
      "defaults read com.apple.dock autohide" => "1",
      "defaults read com.apple.dock orientation" => "right",
      "defaults read com.apple.dock tilesize" => "24",
      "defaults read com.apple.finder AppleShowAllFiles" => "1",
      "defaults read com.apple.AirDrop DiscoverableMode" => "Off",
      "defaults read com.apple.assistant.support 'Assistant Enabled'" => "0",
      "defaults read com.apple.widgets WidgetsEnabled" => "0",
      "defaults read com.apple.menuextra.clock Show24Hour" => "1",
      "defaults read com.apple.WindowManager GloballyEnabled" => "0",
      # Software Updates (system-level, sudo to read)
      "sudo defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall" => "0",
      "sudo defaults read /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall" => "0",
      "defaults read com.apple.HIToolbox AppleDictationAutoEnable" => "0",
      # Trackpad (Bluetooth domain may not persist on a machine without a BT trackpad, so skipped here)
      "defaults read NSGlobalDomain com.apple.trackpad.scaling" => "2.5",
      "defaults read com.apple.AppleMultitouchTrackpad Clicking" => "1",
      "defaults read NSGlobalDomain com.apple.mouse.tapBehavior" => "1",
      "defaults read com.apple.Terminal ApplePressAndHoldEnabled" => "1",
      # Keyboard shortcuts (read from the symbolichotkeys plist via PlistBuddy)
      "/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:64:enabled' ~/Library/Preferences/com.apple.symbolichotkeys.plist" => "false",
      "/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:65:enabled' ~/Library/Preferences/com.apple.symbolichotkeys.plist" => "false",
      "/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:60:enabled' ~/Library/Preferences/com.apple.symbolichotkeys.plist" => "true",
      "/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:60:value:parameters:2' ~/Library/Preferences/com.apple.symbolichotkeys.plist" => "1048576",
      "/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:15:enabled' ~/Library/Preferences/com.apple.symbolichotkeys.plist" => "false",
      "/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:21:enabled' ~/Library/Preferences/com.apple.symbolichotkeys.plist" => "false",
      "/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:26:enabled' ~/Library/Preferences/com.apple.symbolichotkeys.plist" => "false",
      # Git config
      "git config --global user.name" => TEST_GIT_NAME,
      "git config --global user.email" => TEST_GIT_EMAIL,
      "git config --global init.defaultBranch" => "main",
      # Secrets decryption produced files
      "test -f #{GUEST_REPO}/config/personal/git_identity.yml && echo yes" => "yes",
      "test -f #{GUEST_REPO}/config/personal/ssh_config && echo yes" => "yes",
      # SSH key generated
      "test -f ~/.ssh/id_ed25519 && echo yes" => "yes",
      # SSH config installed from personal
      "test -f ~/.ssh/config && echo yes" => "yes",
      # Karabiner config installed
      "test -f ~/.config/karabiner/karabiner.json && echo yes" => "yes",
      # Keyboard layout bundle installed
      %q(test -d "$HOME/Library/Keyboard Layouts/DvorakExt.bundle" && echo yes) => "yes",
      %q(test -f "$HOME/Library/Keyboard Layouts/DvorakExt.bundle/Contents/Info.plist" && echo yes) => "yes",
      # On a fresh VM, inputsources is empty, so the module adds Dvorak Plus
      # to HIToolbox's AppleEnabledInputSources.
      "plutil -extract AppleEnabledInputSources json -o - ~/Library/Preferences/com.apple.HIToolbox.plist" => "Dvorak Plus",
      # Firewall enabled
      "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate" => "enabled",
      # Power management is not verifiable in Tart VMs — there's no real power
      # hardware, so pmset silently drops `-a lowpowermode 0` without persisting
      # anything readable. The module's exit status during setup is the only
      # signal we get in a VM; real hardware is the only honest E2E for pmset.
      # Tools installed (use absolute paths — SSH session has no .zprofile)
      "test -x /opt/homebrew/bin/brew && echo yes" => "yes",
      "ls #{GUEST_REPO}/config/personal/node_modules 2>/dev/null; test -d /Users/#{SSH_USER}/.nvm/versions/node && echo yes" => "yes",
      "test -x /opt/homebrew/bin/claude && echo yes" => "yes",
      "test -x /opt/homebrew/bin/age && echo yes" => "yes",
    }

    failures = []
    checks.each do |cmd_str, expected|
      out, _, status = Open3.capture3(*ssh_cmd(ip, cmd_str))
      actual = out.strip
      if !status.success? || !actual.include?(expected)
        failures << "  FAIL: `#{cmd_str}` — expected '#{expected}', got '#{actual}'"
      end
    end

    if failures.empty?
      log "All #{checks.size} verification checks passed."
    else
      log "#{failures.size}/#{checks.size} checks failed:"
      failures.each { |f| log f }
      abort "[vm-test] Verification failed."
    end
  end

  # Exercise the dedup path: simulate what macOS does when the user enables
  # the layout via the GUI (populating com.apple.inputsources), then re-run
  # the module and assert it removes the now-duplicate HIToolbox entry.
  #
  # If com.apple.inputsources is TCC-locked on the fresh VM (same as on a
  # real Mac once macOS has taken ownership of the file), the seeding step
  # fails; in that case we log a warning and skip rather than fail, since
  # this is a platform limitation, not a code bug.
  def verify_keyboard_layouts_dedup(ip)
    log "Seeding com.apple.inputsources to exercise dedup path..."
    seed = <<~'BASH'
      set -e
      PLIST="$HOME/Library/Preferences/com.apple.inputsources.plist"
      if [ ! -f "$PLIST" ]; then
        defaults write com.apple.inputsources AppleEnabledThirdPartyInputSources -array
      fi
      plutil -replace AppleEnabledThirdPartyInputSources \
        -json '[{"InputSourceKind":"Keyboard Layout","KeyboardLayout ID":-24626,"KeyboardLayout Name":"Dvorak Plus"}]' \
        "$PLIST"
      killall cfprefsd
      sleep 1
      defaults read com.apple.inputsources AppleEnabledThirdPartyInputSources
    BASH
    out, err, status = Open3.capture3(*ssh_cmd(ip, seed))
    unless status.success? && out.include?("Dvorak Plus")
      log "[warn] Could not seed com.apple.inputsources (likely TCC-locked in this VM)."
      log "[warn] stderr: #{err.strip}" unless err.strip.empty?
      log "[warn] Skipping dedup scenario — unit tests cover the logic."
      return
    end

    log "Re-running KeyboardLayouts module..."
    remote = "cd #{Shellwords.escape(GUEST_REPO)} && ruby bin/setup keyboardlayouts"
    sh!(*ssh_cmd(ip, remote))

    log "Verifying Dvorak Plus was removed from HIToolbox (dedup)..."
    check = "plutil -extract AppleEnabledInputSources json -o - ~/Library/Preferences/com.apple.HIToolbox.plist"
    out, _, status = Open3.capture3(*ssh_cmd(ip, check))
    abort "[vm-test] Dedup verify failed: could not read HIToolbox" unless status.success?
    if out.include?("Dvorak Plus")
      abort "[vm-test] Dedup failed: Dvorak Plus still present in HIToolbox after inputsources was seeded\n    got: #{out.strip}"
    end
    log "Dedup scenario passed: HIToolbox no longer contains Dvorak Plus."
  end

  def ssh_cmd(ip, remote_cmd)
    cmd = ["ssh"]
    cmd += ssh_opts
    cmd += ["-i", SSH_KEY] if SSH_KEY
    cmd += ["#{SSH_USER}@#{ip}", remote_cmd]
    cmd
  end

  # String form for rsync's -e flag.
  def ssh_cmd_string
    parts = ["ssh"] + ssh_opts
    parts += ["-i", SSH_KEY] if SSH_KEY
    parts.join(" ")
  end

  def ssh_opts
    # ServerAlive* keeps the SSH connection alive during long-running brew
    # installs (10+ min of silent output is normal). After 6 missed 30-sec
    # pings (~3 min of real silence) we bail, which means a real network
    # drop surfaces quickly instead of hanging indefinitely.
    %w[
      -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/dev/null
      -o LogLevel=ERROR
      -o ConnectTimeout=5
      -o ServerAliveInterval=30
      -o ServerAliveCountMax=6
    ]
  end

  # Cleanup caveat: at_exit runs on normal exit, abort, and typical signals
  # (INT, TERM), but NOT on SIGKILL or a process crash. If this task is
  # kill -9'd, the clone and its /tmp/*.log persist — clean up manually:
  #   tart stop <name> && tart delete <name>
  def install_cleanup_hook
    at_exit do
      if KEEP_ON_EXIT
        log "MAC_SETUP_VM_KEEP=1 — leaving clone #{CLONE_NAME} running for inspection"
        next
      end
      log "Tearing down #{CLONE_NAME}"
      system("tart", "stop", CLONE_NAME, out: File::NULL, err: File::NULL)
      system("tart", "delete", CLONE_NAME, out: File::NULL, err: File::NULL)
    end
  end
end
