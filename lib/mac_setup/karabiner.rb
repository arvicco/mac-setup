# frozen_string_literal: true

require "fileutils"

module MacSetup
  class Karabiner < BaseModule
    CONFIG_SOURCE = File.join("config", "karabiner.json")
    CONFIG_DEST   = File.expand_path("~/.config/karabiner/karabiner.json")

    def run
      install_config
    end

    private

    def install_config
      source = File.join(MacSetup::ROOT, CONFIG_SOURCE)
      unless File.exist?(source)
        logger.warn "No #{CONFIG_SOURCE} found. Skipping."
        return
      end

      if File.exist?(CONFIG_DEST) && File.read(CONFIG_DEST) == File.read(source)
        logger.info "Karabiner config already up to date."
        return
      end

      FileUtils.mkdir_p(File.dirname(CONFIG_DEST))
      FileUtils.cp(source, CONFIG_DEST)
      logger.success "Installed Karabiner config to #{CONFIG_DEST}."
      logger.info "Open Karabiner-Elements and grant permissions when prompted:"
      logger.info "  1. System Settings → Privacy & Security → Input Monitoring → enable Karabiner"
      logger.info "  2. System Settings → Privacy & Security → Accessibility → enable Karabiner"
      logger.info "  3. Allow the system extension when macOS prompts"
    end
  end
end
