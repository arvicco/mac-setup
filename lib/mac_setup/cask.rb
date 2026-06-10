# frozen_string_literal: true

module MacSetup
  class Cask < BaseModule
    DEFAULTBROWSER = Homebrew.bin("defaultbrowser")

    def run
      set_default_browser
    end

    private

    def set_default_browser
      unless File.exist?("/Applications/Google Chrome.app")
        logger.warn "Google Chrome not found — skipping default browser setup."
        return
      end
      unless File.executable?(DEFAULTBROWSER)
        logger.warn "#{DEFAULTBROWSER} not found — ensure Brewfile installed defaultbrowser. Skipping."
        return
      end
      logger.info "Setting Google Chrome as default browser..."
      cmd.run(DEFAULTBROWSER, "chrome", abort_on_fail: false)
    end
  end
end
