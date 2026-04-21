# frozen_string_literal: true

require "test_helper"

class TestTailscale < Minitest::Test
  def setup
    @mod = MacSetup::Tailscale.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
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
end
