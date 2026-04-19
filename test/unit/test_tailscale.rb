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
end
