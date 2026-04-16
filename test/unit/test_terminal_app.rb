# frozen_string_literal: true

require "test_helper"

class TestTerminalApp < Minitest::Test
  def setup
    @logger = MacSetup::Utils::Logger.new
    @cmd = MacSetup::Utils::CommandRunner.new(logger: @logger)
    @mod = MacSetup::TerminalApp.new(logger: @logger, cmd: @cmd)
  end

  def test_base_path_quotes_profile_name
    # Profile names can contain spaces (e.g. "Clear Dark"); PlistBuddy
    # requires them quoted in the path expression.
    path = @mod.send(:base_path, "Clear Dark")
    assert_equal %(:"Window Settings":"Clear Dark":keyMapBoundKeys), path
  end

  def test_base_path_handles_single_word_profile
    path = @mod.send(:base_path, "Basic")
    assert_equal %(:"Window Settings":"Basic":keyMapBoundKeys), path
  end

  def test_shift_return_key_is_literal_shift_plus_unicode_return
    # Stored verbatim in the plist as the 7-char string '$\U000d'.
    # Terminal.app parses '$' as Shift and '\U000d' as U+000D (Return).
    assert_equal '$\U000d', MacSetup::TerminalApp::SHIFT_RETURN_KEY
    assert_equal 7, MacSetup::TerminalApp::SHIFT_RETURN_KEY.length
  end

  def test_shift_return_value_is_esc_cr
    # Stored as the 6-char string '\033\r'. Terminal.app emits ESC+CR
    # when the binding fires.
    assert_equal '\033\r', MacSetup::TerminalApp::SHIFT_RETURN_VALUE
    assert_equal 6, MacSetup::TerminalApp::SHIFT_RETURN_VALUE.length
  end

  def test_module_name
    assert_equal "Terminal App", MacSetup::TerminalApp.module_name
  end

  def test_inherits_from_base_module
    assert MacSetup::TerminalApp < MacSetup::BaseModule
  end
end
