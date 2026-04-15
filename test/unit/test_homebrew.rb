# frozen_string_literal: true

require "test_helper"

class TestHomebrew < Minitest::Test
  def test_module_name
    assert_equal "Homebrew", MacSetup::Homebrew.module_name
  end

  def test_inherits_base_module
    assert MacSetup::Homebrew < MacSetup::BaseModule
  end
end
