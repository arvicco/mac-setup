# frozen_string_literal: true

require "fileutils"

module MacSetup
  class Iterm2 < BaseModule
    SOURCE = File.join("config", "personal", "iterm2.plist")
    DEST   = File.expand_path("~/Library/Preferences/com.googlecode.iterm2.plist")

    def run
      source = File.join(MacSetup::ROOT, SOURCE)
      unless File.exist?(source)
        logger.info "No #{SOURCE}; skipping iTerm2 prefs."
        return
      end

      if File.exist?(DEST) && File.read(DEST, mode: "rb") == File.read(source, mode: "rb")
        logger.info "iTerm2 prefs already up to date."
        return
      end

      # iTerm2 caches prefs in memory and writes them back to disk on quit.
      # Overwriting while it's running would be silently undone.
      if iterm_running?
        logger.warn "iTerm2 is running — quit it first, then re-run. Skipping."
        return
      end

      FileUtils.mkdir_p(File.dirname(DEST))
      FileUtils.cp(source, DEST)
      # cfprefsd caches the plist; kick it so next iTerm2 launch reads the
      # fresh file rather than stale in-memory state.
      cmd.run("killall", "cfprefsd", abort_on_fail: false, quiet: true)
      logger.success "Installed iTerm2 prefs to #{DEST}."
    end

    private

    def iterm_running?
      cmd.success?("pgrep", "-q", "-x", "iTerm2")
    end
  end
end
