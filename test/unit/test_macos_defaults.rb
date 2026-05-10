# frozen_string_literal: true

require "test_helper"

class TestMacosDefaults < Minitest::Test
  def setup
    @mod = MacSetup::MacosDefaults.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
  end

  def test_module_name
    assert_equal "Macos Defaults", MacSetup::MacosDefaults.module_name
  end

  def test_defaults_argv_plain_entry
    entry = {
      "domain" => "com.apple.dock",
      "key"    => "autohide",
      "type"   => "bool",
      "value"  => true,
    }
    assert_equal ["defaults", "write", "com.apple.dock", "autohide", "-bool", "true"],
                 @mod.defaults_argv(entry)
  end

  def test_defaults_argv_sudo_entry
    entry = {
      "domain" => "/Library/Preferences/com.apple.SoftwareUpdate",
      "key"    => "CriticalUpdateInstall",
      "type"   => "bool",
      "value"  => false,
      "sudo"   => true,
    }
    argv = @mod.defaults_argv(entry)
    assert_equal "sudo", argv.first
    assert_equal "defaults", argv[1]
    refute_includes argv, "-currentHost"
  end

  # Array values fan out into N positional argv entries — `defaults write
  # domain key -array v1 v2 v3` is the only correct shape. Used by the
  # com.apple.network.local-network whitelist (RFC1918 CIDR ranges) which
  # exempts those subnets from the macOS Sequoia/Tahoe per-app Local
  # Network permission check.
  def test_defaults_argv_array_value
    entry = {
      "domain" => "com.apple.network.local-network",
      "key"    => "AllowedEthernetLocalNetworkAddresses",
      "type"   => "array",
      "value"  => ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"],
    }
    assert_equal(
      ["defaults", "write", "com.apple.network.local-network",
       "AllowedEthernetLocalNetworkAddresses", "-array",
       "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"],
      @mod.defaults_argv(entry),
    )
  end

  def test_defaults_argv_array_value_with_sudo
    entry = {
      "domain" => "com.apple.network.local-network",
      "key"    => "AllowedWiFiLocalNetworkAddresses",
      "type"   => "array",
      "value"  => ["10.0.0.0/8"],
      "sudo"   => true,
    }
    assert_equal(
      ["sudo", "defaults", "write", "com.apple.network.local-network",
       "AllowedWiFiLocalNetworkAddresses", "-array", "10.0.0.0/8"],
      @mod.defaults_argv(entry),
    )
  end

  def test_defaults_argv_current_host_entry
    entry = {
      "domain"       => "com.apple.controlcenter",
      "key"          => "Sound",
      "type"         => "int",
      "value"        => 18,
      "current_host" => true,
    }
    argv = @mod.defaults_argv(entry)
    # -currentHost must sit after `defaults` and before `write`
    assert_equal "defaults", argv[0]
    assert_equal "-currentHost", argv[1]
    assert_equal "write", argv[2]
    assert_equal "com.apple.controlcenter", argv[3]
    assert_equal "Sound", argv[4]
    assert_equal "-int", argv[5]
    assert_equal "18", argv[6]
  end

  def test_defaults_argv_sudo_plus_current_host
    # Unusual combination but the flags should compose predictably.
    entry = {
      "domain"       => "/Library/Preferences/com.apple.somecontrol",
      "key"          => "Setting",
      "type"         => "int",
      "value"        => 1,
      "sudo"         => true,
      "current_host" => true,
    }
    argv = @mod.defaults_argv(entry)
    assert_equal "sudo", argv[0]
    assert_equal "defaults", argv[1]
    assert_equal "-currentHost", argv[2]
    assert_equal "write", argv[3]
  end

  def test_defaults_argv_coerces_value_to_string
    entry = {
      "domain" => "x", "key" => "y", "type" => "int", "value" => 42,
    }
    assert_equal "42", @mod.defaults_argv(entry).last
  end

  # filter_personal enforces the core-wins rule for the macos_defaults
  # overlay: personal entries with the same (domain, key, current_host)
  # identity as a core entry are dropped before apply, so the core
  # default is the one that wins.

  def core_entry(extra = {})
    { "domain" => "com.apple.dock", "key" => "autohide", "type" => "bool", "value" => true }.merge(extra)
  end

  def test_filter_personal_passes_through_non_colliding_entries
    core = [core_entry]
    personal = [
      { "domain" => "com.apple.dock", "key" => "tilesize", "type" => "int", "value" => 48 },
    ]
    assert_equal personal, @mod.filter_personal(core, personal)
  end

  def test_filter_personal_drops_exact_collision
    core = [core_entry]
    personal = [
      { "domain" => "com.apple.dock", "key" => "autohide", "type" => "bool", "value" => false },
    ]
    assert_empty @mod.filter_personal(core, personal)
  end

  def test_filter_personal_distinguishes_current_host_scoping
    # A core entry at the plain scope does NOT collide with a personal
    # entry at -currentHost scope — they write to different plists.
    core = [{ "domain" => "com.apple.controlcenter", "key" => "Sound", "type" => "bool", "value" => true }]
    personal = [
      { "domain" => "com.apple.controlcenter", "key" => "Sound", "type" => "int", "value" => 18, "current_host" => true },
    ]
    assert_equal personal, @mod.filter_personal(core, personal)
  end

  def test_filter_personal_matches_on_current_host_when_both_set
    core = [
      { "domain" => "com.apple.controlcenter", "key" => "Sound", "type" => "int", "value" => 18, "current_host" => true },
    ]
    personal = [
      { "domain" => "com.apple.controlcenter", "key" => "Sound", "type" => "int", "value" => 8,  "current_host" => true },
    ]
    assert_empty @mod.filter_personal(core, personal)
  end

  # Every auto-update knob under com.apple.SoftwareUpdate must be off.
  # Why: a remote Mac that auto-downloads or auto-installs an OS update can
  # stage it in the background and brick SSH on next reboot ("preparing
  # update" leaves networking down). For dozens of headless Macs this is
  # a regression we cannot detect remotely — keep all of these locked off.
  REQUIRED_SOFTWARE_UPDATE_KEYS = %w[
    AutomaticCheckEnabled
    AutomaticDownload
    AutomaticallyInstallMacOSUpdates
    CriticalUpdateInstall
    ConfigDataInstall
  ].freeze

  def test_macos_defaults_config_disables_every_software_update_auto_knob
    entries = YAML.safe_load(File.read(File.join(MacSetup::ROOT, "config/macos_defaults.yml")))
    sw_entries = entries.select { |e| e["domain"] == "/Library/Preferences/com.apple.SoftwareUpdate" }
    sw_keys = sw_entries.map { |e| e["key"] }

    REQUIRED_SOFTWARE_UPDATE_KEYS.each do |key|
      entry = sw_entries.find { |e| e["key"] == key }
      assert entry, "config/macos_defaults.yml missing SoftwareUpdate key #{key} — present keys: #{sw_keys.inspect}"
      assert_equal false, entry["value"], "SoftwareUpdate.#{key} must be false (got #{entry["value"].inspect})"
      assert_equal true,  entry["sudo"],  "SoftwareUpdate.#{key} must have sudo: true (writes /Library/Preferences)"
    end
  end

  # Both Ethernet and WiFi sides of the per-app Local Network permission
  # must be whitelisted for RFC1918 — without this, macOS Sequoia/Tahoe
  # silently drops outbound packets from any app/CLI that hasn't been
  # granted Local Network access, returning EHOSTUNREACH at sendto. This
  # breaks SSH between local Macs, Tart VMs (bridge100), and anything
  # else on local subnets. The fix is a system-level whitelist (sudo:true)
  # of the three private CIDR ranges. Reboot is required to take effect.
  REQUIRED_LOCAL_NETWORK_KEYS = %w[
    AllowedEthernetLocalNetworkAddresses
    AllowedWiFiLocalNetworkAddresses
  ].freeze

  REQUIRED_RFC1918_RANGES = %w[
    10.0.0.0/8
    172.16.0.0/12
    192.168.0.0/16
  ].freeze

  def test_macos_defaults_config_whitelists_rfc1918_local_network
    entries = YAML.safe_load(File.read(File.join(MacSetup::ROOT, "config/macos_defaults.yml")))
    ln_entries = entries.select { |e| e["domain"] == "com.apple.network.local-network" }
    ln_keys = ln_entries.map { |e| e["key"] }

    REQUIRED_LOCAL_NETWORK_KEYS.each do |key|
      entry = ln_entries.find { |e| e["key"] == key }
      assert entry, "config/macos_defaults.yml missing Local Network key #{key} — present keys: #{ln_keys.inspect}"
      assert_equal "array", entry["type"], "#{key} must be type:array"
      assert_equal true, entry["sudo"], "#{key} must have sudo:true (writes /Library/Preferences)"
      REQUIRED_RFC1918_RANGES.each do |cidr|
        assert_includes entry["value"], cidr,
                        "#{key} must whitelist #{cidr} (current value: #{entry["value"].inspect})"
      end
    end
  end

  def test_filter_personal_keeps_order_of_surviving_entries
    core = [core_entry]
    personal = [
      core_entry("value" => false), # collides, dropped
      { "domain" => "com.apple.dock", "key" => "orientation", "type" => "string", "value" => "bottom" },
      { "domain" => "com.apple.finder", "key" => "ShowPathbar", "type" => "bool", "value" => false },
    ]
    survivors = @mod.filter_personal(core, personal)
    assert_equal 2, survivors.length
    assert_equal "orientation", survivors.first["key"]
    assert_equal "ShowPathbar", survivors.last["key"]
  end
end
