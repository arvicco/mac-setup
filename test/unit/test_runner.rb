# frozen_string_literal: true

require "test_helper"

class TestRunner < Minitest::Test
  def test_modules_list_is_not_empty
    refute_empty MacSetup::Runner::MODULES
  end

  def test_all_modules_inherit_base_module
    MacSetup::Runner::MODULES.each do |mod|
      assert mod < MacSetup::BaseModule, "#{mod} must inherit from BaseModule"
    end
  end

  def test_all_modules_have_a_name
    MacSetup::Runner::MODULES.each do |mod|
      refute_nil mod.module_name
      refute_empty mod.module_name
    end
  end
end
