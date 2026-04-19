# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "yaml"

module MacSetup
  class KeyboardLayouts < BaseModule
    BUNDLES_DIR = File.join("config", "keyboard_layouts")
    CONFIG_FILE = File.join("config", "keyboard_layouts.yml")
    INSTALL_DIR = File.expand_path("~/Library/Keyboard Layouts")
    HITOOLBOX_PLIST = File.expand_path("~/Library/Preferences/com.apple.HIToolbox.plist")
    HITOOLBOX_KEY   = "AppleEnabledInputSources"
    # com.apple.inputsources is where macOS tracks third-party layouts that
    # were enabled via the GUI. It is TCC-protected (we cannot write to it),
    # but we must READ it: if a layout is already listed there, adding it
    # to HIToolbox would produce a duplicate in TIS.
    INPUTSOURCES_PLIST = File.expand_path("~/Library/Preferences/com.apple.inputsources.plist")
    INPUTSOURCES_KEY   = "AppleEnabledThirdPartyInputSources"

    def run
      install_bundles
      update_enabled_sources
    end

    private

    def install_bundles
      source_dir = File.join(MacSetup::ROOT, BUNDLES_DIR)
      unless File.directory?(source_dir)
        logger.warn "No #{BUNDLES_DIR}/ directory. Skipping bundle install."
        return
      end

      bundles = Dir.glob(File.join(source_dir, "*.bundle"))
      if bundles.empty?
        logger.info "No .bundle entries in #{BUNDLES_DIR}/."
        return
      end

      FileUtils.mkdir_p(INSTALL_DIR)
      bundles.each { |path| install_bundle(path) }
    end

    def install_bundle(source)
      name = File.basename(source)
      dest = File.join(INSTALL_DIR, name)

      if File.exist?(dest) && tree_hash(source) == tree_hash(dest)
        logger.info "#{name} already up to date."
        return
      end

      FileUtils.rm_rf(dest) if File.exist?(dest)
      FileUtils.cp_r(source, INSTALL_DIR)
      logger.success "Installed #{name} to #{INSTALL_DIR}."
    end

    def tree_hash(path)
      digest = Digest::SHA256.new
      Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).sort.each do |entry|
        next if File.directory?(entry)
        digest.update(entry.sub(path, ""))
        digest.file(entry)
      end
      digest.hexdigest
    end

    def update_enabled_sources
      config_path = File.join(MacSetup::ROOT, CONFIG_FILE)
      unless File.exist?(config_path)
        logger.info "No #{CONFIG_FILE}; skipping enabled-sources update."
        return
      end

      config = YAML.safe_load(File.read(config_path)) || {}
      enable_specs  = config["enable"]  || []
      disable_specs = config["disable"] || []
      return if enable_specs.empty? && disable_specs.empty?

      current = read_sources(HITOOLBOX_PLIST, HITOOLBOX_KEY)
      if current.nil?
        logger.warn "Could not read #{HITOOLBOX_KEY}; skipping."
        return
      end
      thirdparty = read_sources(INPUTSOURCES_PLIST, INPUTSOURCES_KEY) || []

      target = compute_target(current, enable_specs, disable_specs, thirdparty)
      if target == current
        logger.info "#{HITOOLBOX_KEY} already as desired."
        return
      end

      log_diff(current, target)
      backup_plist
      reload_prefs_before_edit
      write_enabled_sources(target)
      reload_prefs_after_edit
      logger.success "Updated #{HITOOLBOX_KEY}."
      logger.info "Full effect may require logout or reboot."
    end

    # Decide what AppleEnabledInputSources should contain:
    # - remove entries matching any disable spec
    # - for each enable spec:
    #     * if an equivalent is already listed in AppleEnabledThirdPartyInputSources
    #       (the canonical third-party store, TCC-protected so we can't modify it),
    #       ensure it is NOT in HIToolbox — TIS reads both and merges, so a
    #       duplicate produces two menu-bar entries.
    #     * otherwise, add it to HIToolbox if missing.
    def compute_target(current, enable_specs, disable_specs, thirdparty = [])
      filtered = current.reject { |entry| disable_specs.any? { |spec| matches?(entry, spec) } }
      enable_specs.each do |spec|
        if thirdparty.any? { |e| matches?(e, spec) }
          filtered = filtered.reject { |entry| matches?(entry, spec) }
        elsif filtered.none? { |entry| matches?(entry, spec) }
          filtered << build_entry(spec)
        end
      end
      filtered
    end

    def matches?(entry, spec)
      id   = spec["keyboard_layout_id"]
      name = spec["name"]
      return true if id   && entry["KeyboardLayout ID"]   == id
      return true if name && entry["KeyboardLayout Name"] == name
      false
    end

    def build_entry(spec)
      {
        "InputSourceKind"     => "Keyboard Layout",
        "KeyboardLayout ID"   => spec.fetch("keyboard_layout_id"),
        "KeyboardLayout Name" => spec.fetch("name"),
      }
    end

    def read_sources(plist, key)
      # Can't use `plutil -convert json` on the whole HIToolbox plist
      # because its AppleInputSourceUpdateTime date field has no JSON
      # representation and plutil errors out. Extracting one key sidesteps that.
      return nil unless File.exist?(plist)
      stdout, _stderr, status = cmd.run("plutil", "-extract", key, "json", "-o", "-", plist, quiet: true)
      return nil unless status.success?
      JSON.parse(stdout)
    rescue JSON::ParserError
      nil
    end

    def write_enabled_sources(sources)
      cmd.run("plutil", "-replace", HITOOLBOX_KEY, "-json", JSON.generate(sources), HITOOLBOX_PLIST, abort_on_fail: true)
    end

    def backup_plist
      return unless File.exist?(HITOOLBOX_PLIST)
      timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
      backup = "#{HITOOLBOX_PLIST}.bak-#{timestamp}"
      FileUtils.cp(HITOOLBOX_PLIST, backup)
      logger.info "Backed up plist to #{backup}"
    end

    # Flush cfprefsd so its in-memory copy is written to disk before we
    # edit the file. Without this, cfprefsd can overwrite our changes on
    # its next flush.
    def reload_prefs_before_edit
      cmd.run("killall", "cfprefsd", abort_on_fail: false, quiet: true)
    end

    # Invalidate cfprefsd's cache so the next reader loads our changes.
    def reload_prefs_after_edit
      cmd.run("killall", "cfprefsd", abort_on_fail: false, quiet: true)
    end

    def log_diff(before, after)
      added   = after  - before
      removed = before - after
      added.each   { |e| logger.info "  + #{e["KeyboardLayout Name"] || e["Bundle ID"]}" }
      removed.each { |e| logger.info "  - #{e["KeyboardLayout Name"] || e["Bundle ID"]}" }
    end
  end
end
