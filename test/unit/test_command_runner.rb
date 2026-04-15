# frozen_string_literal: true

require "test_helper"

class TestCommandRunner < Minitest::Test
  def setup
    @logger = MacSetup::Utils::Logger.new
    @runner = MacSetup::Utils::CommandRunner.new(logger: @logger)
  end

  def test_run_successful_command
    stdout, _stderr, status = @runner.run("echo hello")
    assert status.success?
    assert_equal "hello\n", stdout
  end

  def test_run_failing_command
    _stdout, _stderr, status = @runner.run("false")
    refute status.success?
  end

  def test_success_returns_true_for_echo
    assert @runner.success?("echo hi")
  end

  def test_success_returns_false_for_false
    refute @runner.success?("false")
  end
end
