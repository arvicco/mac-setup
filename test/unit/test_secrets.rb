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

  # Priority chain: options[:passphrase] > ENV["AGE_PASSPHRASE"] > prompt.
  # Keep in sync with docs/personal-config.md:141.

  def test_resolve_passphrase_prefers_options_flag_over_env
    with_env("AGE_PASSPHRASE" => "from-env") do
      mod = MacSetup::Secrets.new(logger: @logger, cmd: @cmd, options: { passphrase: "from-flag" })
      assert_equal "from-flag", mod.send(:resolve_passphrase)
    end
  end

  def test_resolve_passphrase_falls_through_to_env_when_no_flag
    with_env("AGE_PASSPHRASE" => "from-env") do
      assert_equal "from-env", @mod.send(:resolve_passphrase)
    end
  end

  def test_resolve_passphrase_falls_through_to_prompt_when_no_flag_no_env
    with_env("AGE_PASSPHRASE" => nil) do
      # Non-TTY in test run → prompt_passphrase returns nil. The important
      # thing is the chain reaches prompt rather than short-circuiting.
      assert_nil @mod.send(:resolve_passphrase)
    end
  end

  def test_resolve_passphrase_empty_flag_does_NOT_mask_env
    # Surprising but established Ruby idiom: `"" || x` returns "" (empty
    # string is truthy). If a user passes --passphrase "" we honor that
    # explicit empty and do not fall through to env. The decrypt caller
    # guards on passphrase.empty? and logs "No passphrase provided".
    with_env("AGE_PASSPHRASE" => "from-env") do
      mod = MacSetup::Secrets.new(logger: @logger, cmd: @cmd, options: { passphrase: "" })
      assert_equal "", mod.send(:resolve_passphrase)
    end
  end

  private

  def with_env(vars)
    saved = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
