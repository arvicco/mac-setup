# frozen_string_literal: true

require "test_helper"

class TestKeyboardShortcuts < Minitest::Test
  def setup
    @mod = MacSetup::KeyboardShortcuts.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
  end

  def test_module_name
    assert_equal "Keyboard Shortcuts", MacSetup::KeyboardShortcuts.module_name
  end

  def test_modifier_mask_empty_list_returns_zero
    assert_equal 0, @mod.send(:modifier_mask, [])
  end

  def test_modifier_mask_single_cmd
    assert_equal 1_048_576, @mod.send(:modifier_mask, ["cmd"])
  end

  def test_modifier_mask_cmd_plus_shift
    # cmd 1048576 | shift 131072 = 1179648
    assert_equal 1_179_648, @mod.send(:modifier_mask, ["cmd", "shift"])
  end

  def test_modifier_mask_all_six_modifiers
    total = 1_048_576 + 524_288 + 262_144 + 131_072 + 8_388_608 + 65_536
    assert_equal total, @mod.send(:modifier_mask, %w[cmd option ctrl shift fn caps])
  end

  def test_modifier_mask_order_independent
    a = @mod.send(:modifier_mask, %w[cmd shift])
    b = @mod.send(:modifier_mask, %w[shift cmd])
    assert_equal a, b
  end

  def test_modifier_mask_unknown_modifier_raises
    assert_raises(RuntimeError) { @mod.send(:modifier_mask, ["hyper"]) }
  end
end
