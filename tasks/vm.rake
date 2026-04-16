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
  TEST_HOSTNAME  = ENV.fetch("MAC_SETUP_TEST_HOSTNAME", "mac-setup-test")
  TEST_GIT_NAME  = ENV.fetch("MAC_SETUP_TEST_GIT_NAME", "Mac Setup Test")
  TEST_GIT_EMAIL = ENV.fetch("MAC_SETUP_TEST_GIT_EMAIL", "test@example.com")

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
    run_setup(ip)
    log "✓ Setup completed in VM (ip=#{ip})"
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
      "-e", rsh,
      "#{REPO_ROOT}/", "#{SSH_USER}@#{ip}:#{GUEST_REPO}/"
    )
  end

  def run_setup(ip)
    setup_args = [
      "--all",
      "--hostname", TEST_HOSTNAME,
      "--git-name", TEST_GIT_NAME,
      "--git-email", TEST_GIT_EMAIL
    ]
    log "Running bin/setup #{Shellwords.join(setup_args)}"
    remote = "cd #{Shellwords.escape(GUEST_REPO)} && ruby bin/setup #{Shellwords.join(setup_args)}"
    sh!(*ssh_cmd(ip, remote))
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
