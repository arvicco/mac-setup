# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestGitConfig < Minitest::Test
  def setup
    @mod = MacSetup::GitConfig.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
  end

  def test_inherits_base_module
    assert MacSetup::GitConfig < MacSetup::BaseModule
  end

  # When stdin is not a TTY, prompt() must NOT print anything and must
  # return the `current` value unchanged. Without this guard, a remote
  # `ssh host ruby bin/setup` without --git-name/--git-email would
  # phantom-print a prompt into the log AND silently overwrite the
  # user's real git identity with the empty fallback.
  def test_prompt_returns_current_silently_when_stdin_is_not_a_tty
    fake = StringIO.new("")
    def fake.tty?; false; end
    orig = $stdin
    $stdin = fake
    out, _ = capture_io do
      assert_equal "Existing User", @mod.send(:prompt, "Git name", "Existing User")
    end
    assert_equal "", out, "must NOT print a prompt on non-TTY"
  ensure
    $stdin = orig if orig
  end

  def test_prompt_returns_empty_current_when_no_value_and_no_tty
    fake = StringIO.new("")
    def fake.tty?; false; end
    orig = $stdin
    $stdin = fake
    capture_io do
      assert_equal "", @mod.send(:prompt, "Git email", "")
    end
  ensure
    $stdin = orig if orig
  end
end
