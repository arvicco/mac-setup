# frozen_string_literal: true

require "yaml"

module MacSetup
  class MacosDefaults < BaseModule
    def run
      defaults_file = File.join(MacSetup::ROOT, "config", "macos_defaults.yml")

      unless File.exist?(defaults_file)
        logger.warn "No macos_defaults.yml found. Skipping."
        return
      end

      defaults = YAML.safe_load(File.read(defaults_file))
      return if defaults.nil? || defaults.empty?

      defaults.each do |entry|
        if [entry["domain"], entry["key"], entry["type"], entry["value"]].any? { |v| v.nil? || v.to_s.empty? }
          logger.warn "Skipping malformed defaults entry: #{entry.inspect}"
          next
        end

        flags = []
        flags << "sudo"         if entry["sudo"]
        flags << "currentHost"  if entry["current_host"]
        suffix = flags.empty? ? "" : " (#{flags.join(", ")})"
        logger.info "Setting #{entry["domain"]} #{entry["key"]} = #{entry["value"]}#{suffix}"
        cmd.run(*defaults_argv(entry))
      end

      set_volume
      restart_services
    end

    def restart_services
      logger.info "Restarting affected services..."
      # ControlCenter caches menu-bar item visibility in memory; without a
      # restart our com.apple.controlcenter writes don't show up in the
      # menu bar until the next login.
      %w[Finder Dock ControlCenter].each do |proc_name|
        # Filter by current UID so we match killall's "only my processes"
        # default — a plain `pgrep` sees system-owned duplicates too.
        if cmd.success?("pgrep", "-q", "-U", Process.uid.to_s, proc_name)
          cmd.run("killall", proc_name, abort_on_fail: false)
        else
          logger.info "#{proc_name} not running; skipping restart."
        end
      end
    end

    # Build the argv for `defaults write` based on an entry's flags:
    # - sudo:         prepend `sudo` (needed for /Library/Preferences/*)
    # - current_host: inject `-currentHost` after `defaults`, the form
    #                 macOS uses for per-host preferences like Control
    #                 Center module visibility
    # Flag ordering matters: sudo comes first (it's the outer command),
    # then `defaults`, then `-currentHost` (a flag on `defaults` itself).
    def defaults_argv(entry)
      argv = entry["sudo"] ? ["sudo", "defaults"] : ["defaults"]
      argv << "-currentHost" if entry["current_host"]
      argv + ["write", entry["domain"], entry["key"], "-#{entry["type"]}", entry["value"].to_s]
    end

    private

    def set_volume
      logger.info "Setting alert volume to 50%, output volume to 10%..."
      cmd.run("osascript", "-e", "set volume alert volume 50")
      cmd.run("osascript", "-e", "set volume output volume 10")
    end
  end
end
