# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class TestSecrets < Minitest::Test
  def setup
    @logger = MacSetup::Utils::Logger.new
    @cmd = MacSetup::Utils::CommandRunner.new(logger: @logger)
    @mod = MacSetup::Secrets.new(logger: @logger, cmd: @cmd)
  end

  def test_inherits_from_base_module
    assert MacSetup::Secrets < MacSetup::BaseModule
  end

  def test_module_name
    assert_equal "Secrets", MacSetup::Secrets.module_name
  end

  def test_encrypted_path_points_to_config_personal_age
    path = @mod.send(:encrypted_path)
    assert path.end_with?("config/personal.age"), "Expected path ending in config/personal.age, got #{path}"
  end

  def test_decrypted_path_points_to_config_personal
    path = @mod.send(:decrypted_path)
    assert path.end_with?("config/personal"), "Expected path ending in config/personal, got #{path}"
  end
end
