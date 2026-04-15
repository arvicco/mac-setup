# frozen_string_literal: true

module MacSetup
  class Cask < BaseModule
    def run
      set_default_browser
    end

    private

    def set_default_browser
      if File.exist?("/Applications/Google Chrome.app")
        logger.info "Setting Google Chrome as default browser..."
        cmd.run("defaultbrowser chrome", abort_on_fail: false)
      else
        logger.warn "Google Chrome not found — skipping default browser setup."
      end
    end
  end
end
