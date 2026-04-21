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
