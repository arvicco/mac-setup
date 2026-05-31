# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestPowerManagement < Minitest::Test
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
    @mod = MacSetup::PowerManagement.new(logger: @logger, cmd: @cmd)
  end

  def test_inherits_base_module
    assert MacSetup::PowerManagement < MacSetup::BaseModule
  end

  # `pmset -a sleep 0` only zeros the inactivity timer — it does NOT prevent
  # lid-close sleep, low-battery emergency sleep, or software-initiated sleep
  # via IOPMAssertion. For a home-server pattern (this repo's dominant use
  # case), the actual lockout is `pmset -a disablesleep 1`, which disables
  # all sleep paths at the kernel level. Without it, the machine still
  # sleeps in scenarios the explicit `sleep 0` lines look like they cover.
  def test_run_disables_sleep_globally_via_disablesleep_flag
    capture_io { @mod.run }
    matching = @cmd_calls.select do |c|
      c[:args] == ["sudo", "pmset", "-a", "disablesleep", "1"]
    end
    assert_equal 1, matching.size,
                 "expected exactly one `sudo pmset -a disablesleep 1` invocation; " \
                 "got #{@cmd_calls.size} total cmd calls, args: #{@cmd_calls.map { |c| c[:args] }.inspect}"
  end
end
