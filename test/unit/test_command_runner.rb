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
    refute_includes log, "SECRET",  "secret value must not appear in log"
    refute_includes log, "tskey",   "secret prefix must not appear either"
    assert_match(/redacted/i, log)
    assert_match(/rest/,      log, "non-matching args must echo verbatim")
  end

  # Foot-gun guard: a regex that matches the secret value alone (no
  # prefix anchor) must NOT echo the matched substring. The earlier
  # design appended <redacted> to m[0] — caller-supplied
  # /tskey-[a-z0-9]+/ would have leaked the whole secret. Whole-arg
  # replacement is the safer default.
  def test_redact_whole_arg_replacement_for_value_matching_regex
    log_io = StringIO.new
    logger = MacSetup::Utils::Logger.new(log_file: log_io)
    runner = MacSetup::Utils::CommandRunner.new(logger: logger)
    capture_io do
      runner.run("echo", "tskey-SECRETVALUE",
                 redact: [/tskey-[A-Z0-9]+/])
    end
    log = log_io.string
    refute_includes log, "SECRETVALUE"
    refute_includes log, "tskey-"
    assert_match(/redacted/, log)
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

  # Failure path: tools like `tailscale up` can echo the offending
  # token back in their error output. The redact: option must scrub
  # stderr before it's emitted to the log, otherwise a failed run
  # leaks the secret to log/setup-*.log even though argv was hidden.
  def test_redact_scrubs_stderr_on_failure
    log_io = StringIO.new
    logger = MacSetup::Utils::Logger.new(log_file: log_io)
    runner = MacSetup::Utils::CommandRunner.new(logger: logger)
    # `sh -c 'echo "leak: tskey-SECRET" >&2; exit 1'` — produce the
    # secret on stderr and exit non-zero so the error path fires.
    capture_io do
      runner.run("sh", "-c", "echo 'leak: tskey-SECRET' >&2; exit 1",
                 redact: [/tskey-[A-Z0-9]+/])
    end
    refute_includes log_io.string, "tskey-SECRET",
                    "stderr scrub must remove the secret before logging"
    assert_match(/redacted/, log_io.string)
  end
end
