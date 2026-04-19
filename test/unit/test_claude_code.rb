# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestClaudeCode < Minitest::Test
  def setup
    @src = Dir.mktmpdir("mac-setup-claude-src-")
    @dest = Dir.mktmpdir("mac-setup-claude-dest-")
    @mod = MacSetup::ClaudeCode.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
  end

  def teardown
    FileUtils.remove_entry(@src)  if File.exist?(@src)
    FileUtils.remove_entry(@dest) if File.exist?(@dest)
  end

  def test_module_name
    assert_equal "Claude Code", MacSetup::ClaudeCode.module_name
  end

  def test_inherits_base_module
    assert MacSetup::ClaudeCode < MacSetup::BaseModule
  end

  def test_deploy_setting_file_missing_source_returns_missing
    result = @mod.send(:deploy_setting_file, @src, @dest, "settings.json")
    assert_equal :missing, result
    refute File.exist?(File.join(@dest, "settings.json"))
  end

  def test_deploy_setting_file_installs_when_dest_absent
    File.write(File.join(@src, "settings.json"), %({"theme":"dark"}))
    result = @mod.send(:deploy_setting_file, @src, @dest, "settings.json")
    assert_equal :installed, result
    assert_equal %({"theme":"dark"}), File.read(File.join(@dest, "settings.json"))
  end

  def test_deploy_setting_file_unchanged_when_bytes_match
    File.write(File.join(@src,  "settings.json"), %({"x":1}))
    File.write(File.join(@dest, "settings.json"), %({"x":1}))
    mtime_before = File.stat(File.join(@dest, "settings.json")).mtime
    sleep 0.01
    result = @mod.send(:deploy_setting_file, @src, @dest, "settings.json")
    mtime_after = File.stat(File.join(@dest, "settings.json")).mtime
    assert_equal :unchanged, result
    assert_equal mtime_before, mtime_after
  end

  def test_deploy_setting_file_backs_up_differing_dest
    File.write(File.join(@src,  "settings.json"), %({"x":"new"}))
    File.write(File.join(@dest, "settings.json"), %({"x":"old"}))

    result = @mod.send(:deploy_setting_file, @src, @dest, "settings.json")

    assert_equal :updated, result
    assert_equal %({"x":"new"}), File.read(File.join(@dest, "settings.json"))
    backups = Dir.children(@dest).grep(/settings\.json\.bak-/)
    assert_equal 1, backups.length
    assert_equal %({"x":"old"}), File.read(File.join(@dest, backups.first))
  end

  def test_deploy_setting_file_creates_dest_dir_if_missing
    nested = File.join(@dest, "nested")
    File.write(File.join(@src, "settings.json"), %({}))
    result = @mod.send(:deploy_setting_file, @src, nested, "settings.json")
    assert_equal :installed, result
    assert File.directory?(nested)
    assert File.exist?(File.join(nested, "settings.json"))
  end
end
