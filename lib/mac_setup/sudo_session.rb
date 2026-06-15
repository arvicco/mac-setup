# frozen_string_literal: true

require "open3"

module MacSetup
  # Acquires admin privileges for the duration of a setup run by installing
  # a temporary NOPASSWD entry under /etc/sudoers.d, removed on exit.
  #
  # Replaces the earlier 50s-keepalive-thread design which silently failed
  # when macOS shortened the sudo timestamp_timeout, when brew/cask scripts
  # invoked `sudo -k`, or when the keepalive thread died without surfacing
  # — leading to long brew runs flooded with "sudo: a password is required"
  # mid-flight. Pattern matches install-ssh-controller.sh's NOPASSWD setup
  # on remote targets — proven to survive long brew runs without re-prompts.
  #
  # The sudoers file is pid-uniqued so concurrent mac-setup runs don't
  # collide, and registered for at_exit cleanup so normal exits / aborts /
  # exceptions all remove it. We also trap SIGTERM/SIGINT/SIGHUP and
  # invoke release before exit — the default Ruby handler for these
  # signals does NOT run at_exit hooks, so without the traps a kill
  # (timeout, supervised abort, terminal hangup) would leave a NOPASSWD
  # entry on the target. SIGKILL and kernel panic still leave orphans;
  # the recovery one-liner is documented in README.
  class SudoSession
    TRAPPED_SIGNALS = %w[TERM INT HUP].freeze

    def initialize(logger:)
      @logger = logger
      @sudoers_installed = false
    end

    def acquire
      @logger.info "Some steps require admin privileges."
      unless prime_sudo_password
        @logger.error "Could not acquire sudo (wrong password, dismissed prompt, or no TTY)."
        @logger.error "Re-run after fixing your sudo configuration, or run inside a TTY that can prompt."
        exit 1
      end
      install_temp_nopasswd
      at_exit { release }
      install_signal_traps
    end

    # Best-effort: TERM/INT/HUP arriving mid-run trigger release before
    # exit. If the trap itself fails for any reason (signal masked,
    # nested handler) we still exit — never block on cleanup.
    # Exit code follows shell convention: 128 + signal number, so INT
    # (sig 2) → 130, TERM (15) → 143, HUP (1) → 129.
    SIGNAL_NUMBERS = { "INT" => 2, "TERM" => 15, "HUP" => 1 }.freeze
    def install_signal_traps
      TRAPPED_SIGNALS.each do |sig|
        Signal.trap(sig) do
          release rescue nil
          exit 128 + SIGNAL_NUMBERS.fetch(sig, 0)
        end
      end
    end

    def release
      return unless @sudoers_installed
      system("sudo", "rm", "-f", sudoers_path)
      @sudoers_installed = false
    end

    def sudoers_path
      @sudoers_path ||= "/etc/sudoers.d/mac-setup-#{Process.pid}"
    end

    def sudoers_content
      "#{current_user} ALL=(ALL) NOPASSWD: ALL\n"
    end

    private

    def prime_sudo_password
      system("sudo", "-v")
    end

    def install_temp_nopasswd
      unless write_sudoers_file && chmod_sudoers_file
        @logger.error "Failed to install temporary NOPASSWD at #{sudoers_path}."
        @logger.error "If a partial file was created, remove with: sudo rm -f #{sudoers_path}"
        exit 1
      end
      @sudoers_installed = true
      @logger.info "Granted temporary NOPASSWD via #{sudoers_path} (auto-removed on exit)."
    end

    def write_sudoers_file
      _stdout, _stderr, status = Open3.capture3(
        "sudo", "tee", sudoers_path,
        stdin_data: sudoers_content,
      )
      status.success?
    end

    def chmod_sudoers_file
      system("sudo", "chmod", "440", sudoers_path)
    end

    def current_user
      ENV["USER"] || ENV["LOGNAME"] || `whoami`.strip
    end
  end
end
