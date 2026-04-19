# frozen_string_literal: true

require "fileutils"

module MacSetup
  class Ssh < BaseModule
    SSH_DIR = File.expand_path("~/.ssh")
    SSH_CONFIG_SOURCE = File.join("config", "personal", "ssh_config")
    KNOWN_HOSTS_SOURCE = File.join("config", "personal", "known_hosts")

    # Keys we generate on a fresh Mac. The general-purpose key is for
    # servers/other boxes; the github key is dedicated so that
    # `Host github.com / IdentitiesOnly yes` in ssh_config can pin it.
    # This avoids ever sending unrelated keys to GitHub.
    KEYS = [
      { file: "id_ed25519",        comment: nil },
      { file: "id_ed25519_github", comment: "github" },
    ].freeze

    def run
      KEYS.each { |spec| ensure_key(spec) }
      install_ssh_config
      merge_known_hosts
      configure_ssh_agent
    end

    private

    def ensure_key(spec)
      path = File.join(SSH_DIR, spec[:file])
      if File.exist?(path)
        logger.info "~/.ssh/#{spec[:file]} already exists."
        return
      end
      logger.info "Generating SSH key ~/.ssh/#{spec[:file]}..."
      FileUtils.mkdir_p(SSH_DIR, mode: 0o700)
      args = ["ssh-keygen", "-t", "ed25519", "-f", path, "-N", ""]
      args += ["-C", spec[:comment]] if spec[:comment]
      cmd.run(*args, abort_on_fail: true)
      logger.info "Public key (#{spec[:file]}):"
      puts File.read("#{path}.pub")
    end

    def install_ssh_config
      source = File.join(MacSetup::ROOT, SSH_CONFIG_SOURCE)
      return unless File.exist?(source)

      dest = File.join(SSH_DIR, "config")
      if File.exist?(dest) && File.read(dest) == File.read(source)
        logger.info "~/.ssh/config already up to date."
        return
      end

      FileUtils.mkdir_p(SSH_DIR, mode: 0o700)
      FileUtils.cp(source, dest)
      File.chmod(0o600, dest)
      logger.success "Installed ~/.ssh/config from #{SSH_CONFIG_SOURCE}."
    end

    # Union-merge harvested known_hosts into the local file. Preserves
    # existing entries, appends any new ones, drops exact duplicates.
    # Idempotent — re-running adds nothing. Rotated host keys are a
    # separate SSH problem we don't try to resolve here.
    def merge_known_hosts
      source = File.join(MacSetup::ROOT, KNOWN_HOSTS_SOURCE)
      return unless File.exist?(source)

      dest = File.join(SSH_DIR, "known_hosts")
      source_lines = read_host_lines(source)
      return if source_lines.empty?

      existing = File.exist?(dest) ? read_host_lines(dest) : []
      new_lines = source_lines - existing
      if new_lines.empty?
        logger.info "known_hosts already contains all entries from #{KNOWN_HOSTS_SOURCE}."
        return
      end

      FileUtils.mkdir_p(SSH_DIR, mode: 0o700)
      merged = existing + new_lines
      File.write(dest, merged.join("\n") + "\n")
      File.chmod(0o600, dest)
      logger.success "Merged #{new_lines.length} host entries from #{KNOWN_HOSTS_SOURCE}."
    end

    # Normalizes whitespace and drops blank + comment lines so the set
    # difference works on canonical forms.
    def read_host_lines(path)
      File.readlines(path).map(&:rstrip).reject do |line|
        line.empty? || line.start_with?("#")
      end
    end

    def configure_ssh_agent
      unless agent_reachable?
        logger.info "No ssh-agent available (non-GUI session); skipping keychain add."
        KEYS.each { |spec| logger.info "Run after GUI login: ssh-add --apple-use-keychain ~/.ssh/#{spec[:file]}" }
        return
      end
      KEYS.each do |spec|
        path = File.join(SSH_DIR, spec[:file])
        next unless File.exist?(path)
        logger.info "Adding ~/.ssh/#{spec[:file]} to SSH agent..."
        cmd.run("ssh-add", "--apple-use-keychain", path, abort_on_fail: false)
      end
    end

    # SSH_AUTH_SOCK is set by launchd for GUI sessions (and forwarded when
    # ssh'ing with -A). It's unset in non-interactive SSH, where ssh-add
    # would print "Could not open a connection to your authentication agent".
    def agent_reachable?
      sock = ENV["SSH_AUTH_SOCK"].to_s
      !sock.empty? && File.exist?(sock)
    end
  end
end
