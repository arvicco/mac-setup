# frozen_string_literal: true

require "test_helper"

class TestClaudeCode < Minitest::Test
  def test_module_name
    assert_equal "Claude Code", MacSetup::ClaudeCode.module_name
  end

  def test_inherits_base_module
    assert MacSetup::ClaudeCode < MacSetup::BaseModule
  end
end
