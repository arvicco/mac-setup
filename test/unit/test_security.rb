# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestSecurity < Minitest::Test
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
    @mod = MacSetup::Security.new(logger: @logger, cmd: @cmd)
  end

  def test_inherits_base_module
    assert MacSetup::Security < MacSetup::BaseModule
  end

  # The application firewall is what blocks unsolicited inbound — a
  # home-server without it is exposed on the LAN. This module exists
  # to flip exactly one switch, so the regression check is: did we
  # exec the right argv?
  def test_run_enables_application_firewall
    capture_io { @mod.run }
    matching = @cmd_calls.select do |c|
      c[:args] == ["sudo", MacSetup::Security::FIREWALL_CMD, "--setglobalstate", "on"]
    end
    assert_equal 1, matching.size,
                 "expected exactly one socketfilterfw --setglobalstate on call; got #{@cmd_calls.map { |c| c[:args] }}"
  end
end
