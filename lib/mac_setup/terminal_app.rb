# frozen_string_literal: true

module MacSetup
  # Patches Apple Terminal.app's active profile to bind Shift+Return to
  # ESC+CR, which Claude Code (and other TUI apps that support the
  # meta-prefix convention) interpret as "newline." Terminal.app doesn't
  # support the Kitty keyboard protocol (CSI u), so Shift+Return isn't
  # distinguishable from Return at the PTY level without this workaround.
  #
  # Skips safely if Terminal.app is currently running (its cfprefsd copy
  # would overwrite our edit on exit). Run this module from a different
  # terminal (Ghostty, iTerm2, SSH) or after killing Terminal.app.
  class TerminalApp < BaseModule
    PLIST        = File.expand_path("~/Library/Preferences/com.apple.Terminal.plist")
    PLIST_BUDDY  = "/usr/libexec/PlistBuddy"

    # Key:   "$\U000d"  →  Shift ($) + Return (Unicode U+000D)
    # Value: "\033\r"   →  ESC + CR, same sequence Option+Enter emits
    SHIFT_RETURN_KEY   = '$\U000d'
    SHIFT_RETURN_VALUE = '\033\r'

    def run
      if terminal_running?
        logger.warn "Terminal.app is running — cfprefsd would clobber our edit on exit."
        logger.warn "Quit Terminal.app (or run from Ghostty/iTerm2/SSH) and re-run:"
        logger.warn "  ruby bin/setup TerminalApp"
        return
      end

      profile = active_profile
      unless profile
        logger.warn "Could not read Terminal.app 'Default Window Settings'. Skipping."
        return
      end

      if binding_present?(profile)
        logger.info "Shift+Return binding already present in profile '#{profile}'."
        return
      end

      install_binding(profile)
    end

    private

    def terminal_running?
      cmd.success?("pgrep", "-x", "Terminal")
    end

    def active_profile
      stdout, _, status = cmd.run(
        "defaults", "read", "com.apple.Terminal", "Default Window Settings",
        quiet: true
      )
      status.success? && !stdout.strip.empty? ? stdout.strip : nil
    end

    def binding_present?(profile)
      path = "#{base_path(profile)}:#{SHIFT_RETURN_KEY}"
      cmd.success?(PLIST_BUDDY, "-c", "Print #{path}", PLIST)
    end

    def install_binding(profile)
      ensure_bound_keys_dict(profile)
      path = "#{base_path(profile)}:#{SHIFT_RETURN_KEY}"
      cmd.run(
        PLIST_BUDDY, "-c", "Add #{path} string #{SHIFT_RETURN_VALUE}", PLIST,
        abort_on_fail: true
      )
      # Force cfprefsd to drop its cached copy so the next Terminal.app
      # launch reads the new value from disk.
      cmd.run("killall", "cfprefsd", abort_on_fail: false, quiet: true)
      logger.success "Shift+Return bound to ESC+CR in profile '#{profile}'."
      logger.info "Relaunch Terminal.app for the binding to take effect."
    end

    def ensure_bound_keys_dict(profile)
      path = base_path(profile)
      return if cmd.success?(PLIST_BUDDY, "-c", "Print #{path}", PLIST)

      cmd.run(PLIST_BUDDY, "-c", "Add #{path} dict", PLIST, abort_on_fail: true)
    end

    def base_path(profile)
      %(:"Window Settings":"#{profile}":keyMapBoundKeys)
    end
  end
end
