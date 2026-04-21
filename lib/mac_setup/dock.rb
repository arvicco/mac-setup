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
      apps   = config["apps"]   || []
      remove = config["remove"] || []
      return if apps.empty? && remove.empty?

      changed = 0
      changed += remove_apps(remove)
      changed += add_apps(apps)

      return if changed.zero?
      logger.info "Restarting Dock to apply..."
      cmd.run("killall", "Dock", abort_on_fail: false, quiet: true)
    end

    # Remove stock entries the user doesn't want (Mail, Maps, etc.).
    # `dockutil --remove <label>` exits 0 on success, non-zero when no
    # entry matches — which happens on re-runs and on systems where the
    # app was never pinned. Treat either as "handled"; only count it as
    # a change when the exit was 0 (so we don't restart the Dock for no
    # reason on a clean re-run).
    def remove_apps(labels)
      changed = 0
      labels.each do |label|
        _out, _err, status = cmd.run(
          DOCKUTIL, "--remove", label, "--no-restart",
          abort_on_fail: false, quiet: true,
        )
        if status.success?
          logger.info "Dock: removed #{label}."
          changed += 1
        end
      end
      changed
    end

    def add_apps(app_paths)
      pinned_paths = list_pinned_paths
      changed = 0
      app_paths.each do |app_path|
        unless File.exist?(app_path)
          logger.warn "Dock: #{app_path} not installed; skipping."
          next
        end
        if pinned_paths.include?(normalize_path(app_path))
          logger.info "Dock: #{File.basename(app_path)} already pinned."
          next
        end
        logger.info "Dock: pinning #{File.basename(app_path)}..."
        # --no-restart so we batch the Dock restart at the end; one
        # restart instead of one-per-app avoids the visible flicker.
        cmd.run(DOCKUTIL, "--add", app_path, "--no-restart", abort_on_fail: false)
        changed += 1
      end
      changed
    end

    # Parse `dockutil --list` output for the absolute paths of already-
    # pinned apps. Matching by path (not label) avoids the substring /
    # label-vs-basename ambiguity — dockutil --find "iTerm" would match
    # a pre-existing "iTerm2" label; path match won't.
    def list_pinned_paths
      stdout, _stderr, status = cmd.run(DOCKUTIL, "--list", quiet: true)
      return [] unless status.success?
      parse_pinned_paths(stdout)
    end

    # dockutil --list output (tab-separated):
    #   <label>\tfile:///Applications/Foo.app/\tpersistentApps\t<idx>\t…
    # We extract and normalize the file URL to a filesystem path.
    def parse_pinned_paths(output)
      output.each_line.filter_map do |line|
        parts = line.split("\t")
        next if parts.length < 2
        url = parts[1].strip
        next unless url.start_with?("file://")
        require "uri"
        path = URI.decode_www_form_component(url.sub(%r{\Afile://}, "").sub(%r{/\z}, ""))
        normalize_path(path)
      end
    end

    # macOS is case-insensitive on the default APFS (case-preserving).
    # Normalize to avoid false negatives from mixed-case paths.
    def normalize_path(path)
      path.downcase
    end
  end
end
