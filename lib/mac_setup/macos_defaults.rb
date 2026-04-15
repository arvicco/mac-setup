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

        logger.info "Setting #{domain} #{key} = #{value}"
        cmd.run("defaults write #{domain} #{key} -#{type} #{value}")
      end

      logger.info "Restarting affected services..."
      cmd.run("killall Finder", abort_on_fail: false)
      cmd.run("killall Dock", abort_on_fail: false)
    end
  end
end
