# frozen_string_literal: true

require "fileutils"

module MacSetup
  class Ssh < BaseModule
    SSH_DIR = File.expand_path("~/.ssh")
    SSH_CONFIG_SOURCE = File.join("config", "personal", "ssh_config")

    def run
      generate_key unless key_exists?
      install_ssh_config
      configure_ssh_agent
    end

    private

    def key_exists?
      File.exist?(File.join(SSH_DIR, "id_ed25519"))
    end

    def generate_key
      logger.info "Generating SSH key..."
      Dir.mkdir(SSH_DIR, 0o700) unless File.directory?(SSH_DIR)
      cmd.run(
        'ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""',
        abort_on_fail: true
      )
      logger.info "Public key:"
      puts File.read(File.join(SSH_DIR, "id_ed25519.pub"))
    end

    def install_ssh_config
      source = File.join(MacSetup::ROOT, SSH_CONFIG_SOURCE)
      return unless File.exist?(source)

      dest = File.join(SSH_DIR, "config")
      if File.exist?(dest) && File.read(dest) == File.read(source)
        logger.info "~/.ssh/config already up to date."
        return
      end

      Dir.mkdir(SSH_DIR, 0o700) unless File.directory?(SSH_DIR)
      FileUtils.cp(source, dest)
      File.chmod(0o600, dest)
      logger.success "Installed ~/.ssh/config from #{SSH_CONFIG_SOURCE}."
    end

    def configure_ssh_agent
      logger.info "Adding key to SSH agent..."
      cmd.run("ssh-add --apple-use-keychain ~/.ssh/id_ed25519", abort_on_fail: false)
    end
  end
end
