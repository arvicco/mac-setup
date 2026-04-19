# frozen_string_literal: true

require "test_helper"

class TestKeyboardLayouts < Minitest::Test
  def setup
    @mod = MacSetup::KeyboardLayouts.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
  end

  def test_module_name
    assert_equal "Keyboard Layouts", MacSetup::KeyboardLayouts.module_name
  end

  def test_inherits_base_module
    assert MacSetup::KeyboardLayouts < MacSetup::BaseModule
  end

  DVORAK_CMD = { "InputSourceKind" => "Keyboard Layout", "KeyboardLayout ID" => 16301,  "KeyboardLayout Name" => "DVORAK - QWERTY CMD" }.freeze
  RUSSIAN    = { "InputSourceKind" => "Keyboard Layout", "KeyboardLayout ID" => 19456,  "KeyboardLayout Name" => "Russian" }.freeze
  DVORAK_PLUS = { "InputSourceKind" => "Keyboard Layout", "KeyboardLayout ID" => -24626, "KeyboardLayout Name" => "Dvorak Plus" }.freeze
  PRESS_HOLD = { "Bundle ID" => "com.apple.PressAndHold", "InputSourceKind" => "Non Keyboard Input Method" }.freeze

  DVORAK_PLUS_SPEC    = { "keyboard_layout_id" => -24626, "name" => "Dvorak Plus" }.freeze
  DVORAK_CMD_SPEC     = { "keyboard_layout_id" => 16301,  "name" => "DVORAK - QWERTY CMD" }.freeze

  def compute(current, enable: [], disable: [], thirdparty: [])
    @mod.send(:compute_target, current, enable, disable, thirdparty)
  end

  def test_compute_target_removes_disabled_by_id
    target = compute([DVORAK_CMD, RUSSIAN], disable: [{ "keyboard_layout_id" => 16301 }])
    assert_equal [RUSSIAN], target
  end

  def test_compute_target_removes_disabled_by_name
    target = compute([DVORAK_CMD], disable: [{ "name" => "DVORAK - QWERTY CMD" }])
    assert_empty target
  end

  def test_compute_target_adds_enabled_if_missing
    target = compute([RUSSIAN], enable: [DVORAK_PLUS_SPEC])
    assert_equal [RUSSIAN, DVORAK_PLUS], target
  end

  def test_compute_target_does_not_duplicate_existing_enable
    target = compute([DVORAK_PLUS], enable: [DVORAK_PLUS_SPEC])
    assert_equal [DVORAK_PLUS], target
  end

  def test_compute_target_preserves_order_of_survivors
    current = [RUSSIAN, PRESS_HOLD, DVORAK_CMD]
    target = compute(current, enable: [DVORAK_PLUS_SPEC], disable: [DVORAK_CMD_SPEC])
    assert_equal [RUSSIAN, PRESS_HOLD, DVORAK_PLUS], target
  end

  def test_compute_target_no_op_when_no_changes_needed
    current = [RUSSIAN, DVORAK_PLUS]
    target = compute(current, enable: [DVORAK_PLUS_SPEC], disable: [DVORAK_CMD_SPEC])
    assert_equal current, target
  end

  # Dedup: if an enable spec is already in inputsources (TCC-protected,
  # third-party canonical store), we should NOT add it to HIToolbox.
  def test_compute_target_skips_add_when_present_in_thirdparty
    target = compute([RUSSIAN], enable: [DVORAK_PLUS_SPEC], thirdparty: [DVORAK_PLUS])
    assert_equal [RUSSIAN], target
  end

  # Dedup remediation: if HIToolbox already has a duplicate AND the entry
  # is in inputsources, the duplicate should be REMOVED from HIToolbox.
  def test_compute_target_removes_duplicate_when_present_in_thirdparty
    current = [RUSSIAN, DVORAK_PLUS]
    target = compute(current, enable: [DVORAK_PLUS_SPEC], thirdparty: [DVORAK_PLUS])
    assert_equal [RUSSIAN], target
  end

  # When inputsources has the entry, the disable list for the same layout
  # still removes it from HIToolbox (same effect either way).
  def test_compute_target_disable_still_works_when_thirdparty_present
    current = [DVORAK_PLUS]
    target = compute(current, disable: [DVORAK_PLUS_SPEC], thirdparty: [DVORAK_PLUS])
    assert_empty target
  end
end
