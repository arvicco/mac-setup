# frozen_string_literal: true

require "yaml"

module MacSetup
  class Dock < BaseModule
    CONFIG_FILE = File.join("config", "dock.yml")
    DOCKUTIL = "/opt/homebrew/bin/dockutil"

    def run
      config_path = File.join(MacSetup::ROOT, CONFIG_FILE)
      unless File.exist?(config_path)
        logger.info "No #{CONFIG_FILE}; skipping Dock pin."
        return
      end
      unless File.executable?(DOCKUTIL)
        logger.warn "#{DOCKUTIL} not found — ensure Brewfile installed dockutil."
        return
      end

      config = YAML.safe_load(File.read(config_path)) || {}
      apps = config["apps"] || []
      return if apps.empty?

      added = 0
      apps.each do |app_path|
        unless File.exist?(app_path)
          logger.warn "Dock: #{app_path} not installed; skipping."
          next
        end
        if already_pinned?(app_path)
          logger.info "Dock: #{File.basename(app_path)} already pinned."
          next
        end
        logger.info "Dock: pinning #{File.basename(app_path)}..."
        # --no-restart so we batch the Dock restart at the end; one
        # restart instead of one-per-app avoids the visible flicker.
        cmd.run(DOCKUTIL, "--add", app_path, "--no-restart", abort_on_fail: false)
        added += 1
      end

      return if added.zero?
      logger.info "Restarting Dock to apply..."
      cmd.run("killall", "Dock", abort_on_fail: false, quiet: true)
    end

    # `dockutil --find <item>` exits 0 when the item is already anywhere
    # in the dock (any section), non-zero otherwise. Sidesteps the
    # label-vs-basename mismatches that would hit when parsing --list
    # output by hand (e.g. iTerm2.app filesystem basename "iTerm" vs
    # dockutil label "iTerm").
    def already_pinned?(app_path)
      cmd.success?(DOCKUTIL, "--find", File.basename(app_path, ".app"))
    end
  end
end
