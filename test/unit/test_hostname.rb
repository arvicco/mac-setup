# frozen_string_literal: true

require "test_helper"

class TestHostname < Minitest::Test
  def test_module_name
    assert_equal "Hostname", MacSetup::Hostname.module_name
  end

  def test_inherits_base_module
    assert MacSetup::Hostname < MacSetup::BaseModule
  end

  def test_scutil_keys_contains_all_three_names
    keys = MacSetup::Hostname::SCUTIL_KEYS
    assert_includes keys, "HostName"
    assert_includes keys, "ComputerName"
    assert_includes keys, "LocalHostName"
    assert_equal 3, keys.length
  end
end
