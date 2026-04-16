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

  # Exec form bypasses the shell, so args containing shell metacharacters
  # are passed as literal arguments — no injection.
  def test_exec_form_treats_metacharacters_literally
    injection = "$(echo PWNED)"
    stdout, _stderr, status = @runner.run("echo", injection, quiet: true)
    assert status.success?
    assert_equal "#{injection}\n", stdout
  end

  def test_exec_form_success
    assert @runner.success?("true")
    refute @runner.success?("false")
  end

  def test_run_with_no_args_raises
    assert_raises(ArgumentError) { @runner.run(quiet: true) }
  end
end
