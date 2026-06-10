# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestAutoLogin < Minitest::Test
  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @cmd_calls = []
    recorder = @cmd_calls
    cmd = Object.new
    cmd.define_singleton_method(:run) do |*args, **kwargs|
      recorder << {args: args, kwargs: kwargs}
      ["", "", Struct.new(:success?, :exitstatus).new(true, 0)]
    end
    @cmd = cmd
  end

  def test_inherits_base_module
    assert MacSetup::AutoLogin < MacSetup::BaseModule
  end

  # Opt-in design: the autologin.yml ships in every personal.age archive,
  # but only home-server installs (those passing --autologin) should
  # actually enable boot-time auto-login. Without the flag, the module
  # must be a no-op regardless of whether the yml exists.
  def test_run_is_noop_without_autologin_flag
    mod = MacSetup::AutoLogin.new(logger: @logger, cmd: @cmd, options: {})
    capture_io { mod.run }
    assert_empty @cmd_calls, "must not invoke sysadminctl without --autologin"
    assert_match(/Auto-login not enabled/, @log_io.string)
  end
end
