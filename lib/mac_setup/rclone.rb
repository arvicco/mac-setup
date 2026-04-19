# frozen_string_literal: true

require "fileutils"

module MacSetup
  class Rclone < BaseModule
    CONFIG_SOURCE = File.join("config", "personal", "rclone.conf")
    CONFIG_DEST   = File.expand_path("~/.config/rclone/rclone.conf")

    def run
      source = File.join(MacSetup::ROOT, CONFIG_SOURCE)
      unless File.exist?(source)
        logger.info "No #{CONFIG_SOURCE}; skipping rclone config."
        return
      end

      if File.exist?(CONFIG_DEST) && File.read(CONFIG_DEST) == File.read(source)
        logger.info "rclone.conf already up to date."
        return
      end

      FileUtils.mkdir_p(File.dirname(CONFIG_DEST))
      FileUtils.cp(source, CONFIG_DEST)
      # rclone refuses to load configs with loose permissions (contains OAuth
      # tokens for all configured remotes).
      File.chmod(0o600, CONFIG_DEST)
      logger.success "Installed rclone.conf to #{CONFIG_DEST}."
    end
  end
end
