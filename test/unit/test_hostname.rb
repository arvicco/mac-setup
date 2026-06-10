# frozen_string_literal: true

require "test_helper"
require "stringio"

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

  # Closed-stdin (non-TTY) must NOT block. The remote-setup docs tell
  # users to pass --hostname, but a forgetful user running over SSH
  # without that flag would otherwise hang forever on $stdin.gets.
  # Conservative behavior: log a clear "kept current" line and move on.
  def test_prompt_for_hostname_returns_blank_and_does_not_print_when_stdin_is_not_a_tty
    mod = MacSetup::Hostname.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
    fake = StringIO.new("")
    def fake.tty?; false; end
    orig = $stdin
    $stdin = fake
    out, _ = capture_io do
      result = mod.send(:prompt_for_hostname, "old-name")
      assert_equal "", result
    end
    assert_equal "", out, "must NOT print a prompt when stdin is not a TTY (would only confuse the log)"
  ensure
    $stdin = orig if orig
  end
end
