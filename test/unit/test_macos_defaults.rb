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
end
