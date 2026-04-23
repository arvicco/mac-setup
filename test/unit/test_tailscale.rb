# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestTailscale < Minitest::Test
  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @mod = MacSetup::Tailscale.new(
      logger: @logger,
      cmd: MacSetup::Utils::CommandRunner.new(logger: @logger),
    )
  end

  def stub_state(formula:, cask:, config_present: false)
    @mod.define_singleton_method(:formula_installed?) { formula }
    @mod.define_singleton_method(:cask_installed?) { cask }
    @mod.define_singleton_method(:config_present?) { config_present }
  end

  # capture_io silences stdout/stderr for the block; assertions run
  # against the Logger's log_file buffer (@log_io) instead.
  def silently
    capture_io { yield }
  end

  def test_module_name
    assert_equal "Tailscale", MacSetup::Tailscale.module_name
  end

  def test_inherits_base_module
    assert MacSetup::Tailscale < MacSetup::BaseModule
  end

  def test_build_key_spec_encodes_required_fields
    spec = @mod.send(:build_key_spec, ["tag:home-server"])
    create = spec.dig("capabilities", "devices", "create")
    assert_equal false, create["reusable"]
    assert_equal false, create["ephemeral"]
    assert_equal true,  create["preauthorized"]
    assert_equal ["tag:home-server"], create["tags"]
    assert_operator spec["expirySeconds"], :>, 0
  end

  def test_build_key_spec_passes_multiple_tags_through
    spec = @mod.send(:build_key_spec, ["tag:home-server", "tag:laptop"])
    assert_equal ["tag:home-server", "tag:laptop"], spec.dig("capabilities", "devices", "create", "tags")
  end

  # missing_or_placeholder catches the three "not ready to mint a key"
  # cases: key literally missing from YAML (nil), empty string, and the
  # REPLACE_ME sentinel from the harvester template.
  def test_missing_or_placeholder_detects_nil
    assert_equal ["oauth_client_id"],
                 @mod.missing_or_placeholder("oauth_client_id" => nil, "oauth_client_secret" => "real")
  end

  def test_missing_or_placeholder_detects_empty_string
    assert_equal ["oauth_client_secret"],
                 @mod.missing_or_placeholder("oauth_client_id" => "real", "oauth_client_secret" => "")
  end

  def test_missing_or_placeholder_detects_replace_me_sentinel
    result = @mod.missing_or_placeholder(
      "oauth_client_id" => "REPLACE_ME",
      "oauth_client_secret" => "REPLACE_ME",
    )
    assert_equal ["oauth_client_id", "oauth_client_secret"], result
  end

  def test_missing_or_placeholder_ignores_whitespace_around_replace_me
    result = @mod.missing_or_placeholder("oauth_client_id" => "  REPLACE_ME  ")
    assert_equal ["oauth_client_id"], result
  end

  def test_missing_or_placeholder_passes_real_values_through
    assert_empty @mod.missing_or_placeholder(
      "oauth_client_id" => "tskey-client-abc123",
      "oauth_client_secret" => "tskey-client-secret-xyz",
    )
  end

  # Role detection: the module must not try to set up the headless daemon
  # on a Mac that has the GUI cask installed (and vice versa). Running
  # both simultaneously registers the Mac twice in the tailnet.
  def test_run_errors_when_both_formula_and_cask_are_installed
    stub_state(formula: true, cask: true)
    silently { @mod.run }
    assert_operator @logger.error_count, :>, 0
    assert_match(/Both tailscale formula and tailscale-app cask/, @log_io.string)
    assert_match(/admin console.*noto/, @log_io.string)
  end

  def test_run_skips_headless_setup_when_only_cask_is_installed
    stub_state(formula: false, cask: true)
    silently { @mod.run }
    assert_equal 0, @logger.error_count
    assert_match(/GUI app detected.*[Ss]kipping/, @log_io.string)
  end

  def test_run_warns_when_config_present_but_no_package_installed
    stub_state(formula: false, cask: false, config_present: true)
    silently { @mod.run }
    assert_match(/exists but no tailscale package is installed/, @log_io.string)
  end

  def test_run_silently_skips_when_neither_package_nor_config_present
    stub_state(formula: false, cask: false, config_present: false)
    silently { @mod.run }
    assert_equal 0, @logger.error_count
    assert_match(/No .*tailscale\.yml.*skipping/, @log_io.string)
  end
end
