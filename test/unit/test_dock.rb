# frozen_string_literal: true

require "test_helper"

class TestDock < Minitest::Test
  def test_module_name
    assert_equal "Dock", MacSetup::Dock.module_name
  end

  def test_inherits_base_module
    assert MacSetup::Dock < MacSetup::BaseModule
  end
end
