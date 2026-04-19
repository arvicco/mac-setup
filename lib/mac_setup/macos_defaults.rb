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
        domain = entry["domain"]
        key = entry["key"]
        type = entry["type"]
        value = entry["value"]
        use_sudo = entry["sudo"] == true

        if [domain, key, type, value].any? { |v| v.nil? || v.to_s.empty? }
          logger.warn "Skipping malformed defaults entry: #{entry.inspect}"
          next
        end

        logger.info "Setting #{domain} #{key} = #{value}#{' (sudo)' if use_sudo}"
        argv = use_sudo ? ["sudo", "defaults"] : ["defaults"]
        cmd.run(*argv, "write", domain, key, "-#{type}", value.to_s)
      end

      set_volume
      restart_services
    end

    def restart_services
      logger.info "Restarting affected services..."
      %w[Finder Dock].each do |proc_name|
        # Filter by current UID so we match killall's "only my processes"
        # default — a plain `pgrep` sees system-owned duplicates too.
        if cmd.success?("pgrep", "-q", "-U", Process.uid.to_s, proc_name)
          cmd.run("killall", proc_name, abort_on_fail: false)
        else
          logger.info "#{proc_name} not running; skipping restart."
        end
      end
    end

    private

    def set_volume
      logger.info "Setting alert volume to 50%, output volume to 10%..."
      cmd.run("osascript", "-e", "set volume alert volume 50")
      cmd.run("osascript", "-e", "set volume output volume 10")
    end
  end
end
