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

  # stream: inherits stdout/stderr to the parent; captured output is empty
  # strings but the exit status is correct. Lets callers show live progress
  # for long-running commands (brew bundle, nvm install, etc.) instead of
  # buffering until completion.

  def test_stream_mode_returns_empty_captures
    stdout, stderr, status = @runner.run("true", stream: true, quiet: true)
    assert status.success?
    assert_equal "", stdout
    assert_equal "", stderr
  end

  def test_stream_mode_propagates_non_zero_status
    _stdout, _stderr, status = @runner.run("false", stream: true, quiet: true)
    refute status.success?
    assert_equal 1, status.exitstatus
  end

  def test_stream_mode_accepts_exec_form_args
    # Key property: stream mode must work with exec-form invocation too,
    # since that's how we call brew bundle, ssh-keygen, pmset, etc.
    _stdout, _stderr, status = @runner.run("true", "anything", stream: true, quiet: true)
    assert status.success?
  end

  # Redaction: callers pass a list of regexes; matching args in the
  # echoed `$ cmd` line are rewritten before logging. Real values still
  # reach exec, so the command behavior is unchanged. Prevents future
  # modules from leaking secrets via the log just by forgetting
  # `quiet: true`.
  def test_redact_rewrites_matching_args_in_echo_only
    log_io = StringIO.new
    logger = MacSetup::Utils::Logger.new(log_file: log_io)
    runner = MacSetup::Utils::CommandRunner.new(logger: logger)
    capture_io do
      runner.run("echo", "--auth-key=tskey-SECRET", "rest",
                 redact: [/\A--auth-key=/])
    end
    log = log_io.string
    # Security property: the real secret never reaches the log, the
    # redacted marker does, and the surrounding args are still echoed.
    # The line is Shellwords-escaped so `=` and `<>` show up backslashed
    # — that's fine, we just need the strings recognizable.
    refute_includes log, "SECRET",  "secret value must not appear in log"
    assert_match(/--auth-key/, log)
    assert_match(/redacted/i,  log)
    assert_match(/rest/,       log, "non-matching args must echo verbatim")
  end

  def test_redact_does_not_affect_actual_command_execution
    # The exec form must still see the real value — only the LOG is
    # rewritten. Use `echo` so we can compare stdout to the literal.
    stdout, _, status = @runner.run(
      "echo", "--token=abc123",
      redact: [/\A--token=/], quiet: true,
    )
    assert status.success?
    assert_equal "--token=abc123\n", stdout
  end

  def test_redact_with_quiet_does_not_log_anything
    log_io = StringIO.new
    logger = MacSetup::Utils::Logger.new(log_file: log_io)
    runner = MacSetup::Utils::CommandRunner.new(logger: logger)
    capture_io do
      runner.run("echo", "--auth-key=tskey-SECRET",
                 redact: [/\A--auth-key=/], quiet: true)
    end
    assert_equal "", log_io.string
  end
end
