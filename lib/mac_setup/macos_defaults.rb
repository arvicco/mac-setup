# frozen_string_literal: true

require "set"
require "yaml"

module MacSetup
  class MacosDefaults < BaseModule
    CORE_FILE     = File.join("config", "macos_defaults.yml")
    PERSONAL_FILE = File.join("config", "personal", "macos_defaults.yml")

    def run
      core = load_entries(File.join(MacSetup::ROOT, CORE_FILE))
      if core.nil?
        logger.warn "No #{CORE_FILE} found. Skipping."
        return
      end
      personal = load_entries(File.join(MacSetup::ROOT, PERSONAL_FILE)) || []
      applicable_personal = filter_personal(core, personal)

      (personal - applicable_personal).each do |entry|
        logger.info "Skipping personal override for #{entry["domain"]} #{entry["key"]}: core has precedence"
      end

      all_entries = core + applicable_personal
      return if all_entries.empty?

      all_entries.each { |entry| apply_entry(entry) }

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

    # Drop personal entries that collide with a core entry on the
    # (domain, key, current_host) identity triple. Core wins — those
    # settings are deliberate defaults meant to ship on every install.
    # The overlay is for adding NEW entries, not overriding core.
    def filter_personal(core_entries, personal_entries)
      core_ids = core_entries.map { |e| entry_id(e) }.to_set
      personal_entries.reject { |e| core_ids.include?(entry_id(e)) }
    end

    private

    # sudo doesn't participate in identity — a key either has sudo or it
    # doesn't based on which plist it writes to. (domain, key,
    # current_host) uniquely identifies an applied setting.
    def entry_id(entry)
      [entry["domain"], entry["key"], !!entry["current_host"]]
    end

    def load_entries(path)
      return nil unless File.exist?(path)
      data = YAML.safe_load(File.read(path))
      return [] if data.nil?
      data
    end

    def apply_entry(entry)
      if [entry["domain"], entry["key"], entry["type"], entry["value"]].any? { |v| v.nil? || v.to_s.empty? }
        logger.warn "Skipping malformed defaults entry: #{entry.inspect}"
        return
      end

      flags = []
      flags << "sudo"         if entry["sudo"]
      flags << "currentHost"  if entry["current_host"]
      suffix = flags.empty? ? "" : " (#{flags.join(", ")})"
      logger.info "Setting #{entry["domain"]} #{entry["key"]} = #{entry["value"]}#{suffix}"
      cmd.run(*defaults_argv(entry))
    end

    def set_volume
      logger.info "Setting alert volume to 50%, output volume to 10%..."
      cmd.run("osascript", "-e", "set volume alert volume 50")
      cmd.run("osascript", "-e", "set volume output volume 10")
    end
  end
end
