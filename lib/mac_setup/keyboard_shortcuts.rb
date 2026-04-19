# frozen_string_literal: true

require "yaml"

module MacSetup
  class KeyboardShortcuts < BaseModule
    PLIST = File.expand_path("~/Library/Preferences/com.apple.symbolichotkeys.plist")
    PLIST_BUDDY = "/usr/libexec/PlistBuddy"
    ACTIVATE_SETTINGS = "/System/Library/PrivateFrameworks/" \
      "SystemAdministration.framework/Resources/activateSettings"

    # Bitmask values from <Carbon/Carbon.h>; summed per entry's `modifiers:` list.
    MODIFIER_MASKS = {
      "cmd"    => 1_048_576,
      "option" => 524_288,
      "ctrl"   => 262_144,
      "shift"  => 131_072,
      "fn"     => 8_388_608,
      "caps"   => 65_536,
    }.freeze

    def run
      config_file = File.join(MacSetup::ROOT, "config", "keyboard_shortcuts.yml")
      unless File.exist?(config_file)
        logger.warn "No keyboard_shortcuts.yml found. Skipping."
        return
      end

      entries = YAML.safe_load(File.read(config_file))
      return if entries.nil? || entries.empty?

      ensure_plist_exists
      # Flush cfprefsd before editing on disk so its in-memory copy
      # doesn't overwrite PlistBuddy's writes on its next sync. See the
      # same pattern in KeyboardLayouts.
      cmd.run("killall", "cfprefsd", abort_on_fail: false, quiet: true)
      entries.each { |entry| apply_entry(entry) }
      reload_prefs
    end

    private

    # PlistBuddy needs the file to exist; `defaults write -dict` seeds it
    # with an empty AppleSymbolicHotKeys dict if missing, and is a no-op if
    # the key is already populated.
    def ensure_plist_exists
      return if cmd.success?("defaults", "read", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys")
      cmd.run("defaults", "write", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys", "-dict")
    end

    def apply_entry(entry)
      id      = entry["id"]
      enabled = entry["enabled"] ? true : false
      note    = entry["note"]

      logger.info "Shortcut #{id}#{" (#{note})" if note}: #{enabled ? 'enabled' : 'disabled'}"

      # Delete-then-add is idempotent: it doesn't matter whether the ID
      # existed before, we always end up with our exact structure.
      plist_buddy("Delete :AppleSymbolicHotKeys:#{id}", allow_fail: true)
      plist_buddy("Add :AppleSymbolicHotKeys:#{id} dict")
      plist_buddy("Add :AppleSymbolicHotKeys:#{id}:enabled bool #{enabled}")

      return unless entry["ascii"] && entry["keycode"]

      mask = modifier_mask(entry["modifiers"] || [])
      plist_buddy("Add :AppleSymbolicHotKeys:#{id}:value dict")
      plist_buddy("Add :AppleSymbolicHotKeys:#{id}:value:type string standard")
      plist_buddy("Add :AppleSymbolicHotKeys:#{id}:value:parameters array")
      plist_buddy("Add :AppleSymbolicHotKeys:#{id}:value:parameters:0 integer #{entry['ascii']}")
      plist_buddy("Add :AppleSymbolicHotKeys:#{id}:value:parameters:1 integer #{entry['keycode']}")
      plist_buddy("Add :AppleSymbolicHotKeys:#{id}:value:parameters:2 integer #{mask}")
    end

    def modifier_mask(modifiers)
      modifiers.sum(0) { |m| MODIFIER_MASKS.fetch(m) { raise "Unknown modifier: #{m}" } }
    end

    def plist_buddy(command, allow_fail: false)
      if allow_fail
        cmd.success?(PLIST_BUDDY, "-c", command, PLIST)
      else
        cmd.run(PLIST_BUDDY, "-c", command, PLIST, abort_on_fail: false)
      end
    end

    # cfprefsd caches plists; without this the next login reads stale values.
    # activateSettings tells WindowServer/HIToolbox to re-read symbolichotkeys
    # so bindings take effect without a logout.
    def reload_prefs
      logger.info "Reloading preferences..."
      # quiet: cfprefsd is not running yet on a fresh SSH session for this
      # user; the resulting "No matching processes" error is expected and
      # should not look like a failure in the log.
      cmd.run("killall", "cfprefsd", abort_on_fail: false, quiet: true)
      cmd.run(ACTIVATE_SETTINGS, "-u", abort_on_fail: false)
    end
  end
end
