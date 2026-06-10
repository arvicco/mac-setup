# frozen_string_literal: true

require "test_helper"

class TestRunner < Minitest::Test
  def test_modules_list_is_not_empty
    refute_empty MacSetup::Runner::MODULES
  end

  def test_all_modules_inherit_base_module
    MacSetup::Runner::MODULES.each do |mod|
      assert mod < MacSetup::BaseModule, "#{mod} must inherit from BaseModule"
    end
  end

  def test_all_modules_have_a_name
    MacSetup::Runner::MODULES.each do |mod|
      refute_nil mod.module_name
      refute_empty mod.module_name
    end
  end

  # Catches the easy "forgot to add to Runner::MODULES" mistake when a new
  # module file is dropped into lib/mac_setup/.
  def test_every_module_file_is_registered
    module_files = Dir[File.expand_path("../../lib/mac_setup/*.rb", __dir__)]
      .map { |p| File.basename(p, ".rb") }
      .reject { |n| %w[base_module runner harvester].include?(n) }

    registered = MacSetup::Runner::MODULES.map do |mod|
      # e.g. MacSetup::GitConfig -> "git_config"
      mod.name.split("::").last.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    missing = module_files - registered
    assert_empty missing, "These module files are not in Runner::MODULES: #{missing.join(', ')}"
  end

  # Killer regression test: any module that reads from config/personal/*
  # MUST run after Secrets (which decrypts the archive at runtime). If a
  # module's source references "config/personal" but sits earlier in
  # Runner::MODULES, the file won't exist when that module runs and the
  # personal logic silently no-ops. This exact bug went unnoticed for
  # months in Homebrew, where `config/personal/Brewfile` was checked at
  # MODULES idx 1 (before Secrets at idx 2) so personal package overlays
  # never installed — the user noticed only when tailscale-app (the only
  # entry in their personal Brewfile) was missing post-install.
  #
  # We grep module source files for the literal "config/personal" string
  # because every consuming module references the path that way. Skip
  # Secrets itself (owns the dir) and Harvester (writes outside the
  # MODULES execution flow).
  def test_modules_reading_personal_config_run_after_secrets
    secrets_idx = MacSetup::Runner::MODULES.index(MacSetup::Secrets)
    refute_nil secrets_idx, "Secrets must be registered in MODULES"

    lib_dir = File.expand_path("../../lib/mac_setup", __dir__)
    Dir["#{lib_dir}/*.rb"].each do |file|
      basename = File.basename(file, ".rb")
      next if %w[secrets harvester].include?(basename)
      # Strip comments before grepping so an explanatory comment that
      # mentions "config/personal" doesn't flag a module that actually
      # no longer reads from the directory.
      code_only = File.read(file).each_line.reject { |l| l.strip.start_with?("#") }.join
      next unless code_only.match?(%r{config/personal})

      class_name = basename.split("_").map(&:capitalize).join
      next unless MacSetup.const_defined?(class_name)
      klass = MacSetup.const_get(class_name)
      next unless MacSetup::Runner::MODULES.include?(klass)

      klass_idx = MacSetup::Runner::MODULES.index(klass)
      assert klass_idx > secrets_idx,
             "#{klass} reads config/personal/ (per its source) but runs at MODULES idx #{klass_idx}, " \
             "before Secrets at idx #{secrets_idx}. config/personal/ doesn't exist on disk until " \
             "Secrets decrypts it — this module's personal logic will silently no-op."
    end
  end

  def test_dotfiles_runs_before_claude_code
    modules = MacSetup::Runner::MODULES
    dotfiles_idx = modules.index(MacSetup::Dotfiles)
    claude_idx   = modules.index(MacSetup::ClaudeCode)
    refute_nil dotfiles_idx, "Dotfiles must be registered in Runner::MODULES"
    refute_nil claude_idx,   "ClaudeCode must be registered in Runner::MODULES"
    assert_operator dotfiles_idx, :<, claude_idx,
                    "Dotfiles must precede ClaudeCode (hooks symlink depends on dotfiles)"
  end

  # cleanup_secrets removes the decrypted config/personal/ tree on success
  # so plaintext secrets (gh_token, tailscale OAuth client_secret, autologin
  # password) don't sit around on the target after a one-shot bootstrap.
  # Opt-in via --cleanup-secrets — re-runs that need to tweak config will
  # still re-decrypt from personal.age.
  def make_runner_with_personal_dir(tmpdir, cleanup:)
    personal = File.join(tmpdir, "personal")
    FileUtils.mkdir_p(personal)
    File.write(File.join(personal, "gh_token"), "ghp_secret")

    runner = MacSetup::Runner.new
    runner.instance_variable_set(:@options, cleanup ? {cleanup_secrets: true} : {})
    runner.define_singleton_method(:decrypted_personal_path) { personal }
    [runner, personal]
  end

  def test_cleanup_secrets_removes_personal_dir_when_flag_set_and_no_errors
    Dir.mktmpdir do |tmpdir|
      runner, personal = make_runner_with_personal_dir(tmpdir, cleanup: true)
      logger = MacSetup::Utils::Logger.new
      capture_io { runner.send(:cleanup_secrets, logger) }
      refute File.exist?(personal), "personal/ must be removed after success + flag"
    end
  end

  def test_cleanup_secrets_keeps_personal_dir_when_errors_present
    Dir.mktmpdir do |tmpdir|
      runner, personal = make_runner_with_personal_dir(tmpdir, cleanup: true)
      logger = MacSetup::Utils::Logger.new
      capture_io do
        logger.error("simulated module failure")
        runner.send(:cleanup_secrets, logger)
      end
      assert File.directory?(personal),
             "personal/ must be preserved when modules errored — user needs it to debug/re-run"
      assert_equal 1, Dir.children(personal).count { |f| f == "gh_token" }
    end
  end

  def test_cleanup_secrets_no_op_when_flag_not_set
    Dir.mktmpdir do |tmpdir|
      runner, personal = make_runner_with_personal_dir(tmpdir, cleanup: false)
      logger = MacSetup::Utils::Logger.new
      capture_io { runner.send(:cleanup_secrets, logger) }
      assert File.directory?(personal),
             "personal/ must be kept when --cleanup-secrets was not passed (opt-in)"
    end
  end

  def test_cleanup_secrets_silent_when_personal_dir_does_not_exist
    Dir.mktmpdir do |tmpdir|
      nonexistent = File.join(tmpdir, "nonexistent")
      runner = MacSetup::Runner.new
      runner.instance_variable_set(:@options, {cleanup_secrets: true})
      runner.define_singleton_method(:decrypted_personal_path) { nonexistent }
      logger = MacSetup::Utils::Logger.new
      capture_io { runner.send(:cleanup_secrets, logger) }
      # Should not raise; nothing to assert beyond that
      pass
    end
  end

  # --cleanup-secrets must also nuke config/personal.bak-*/ directories.
  # Otherwise a re-decrypt followed by --cleanup-secrets leaves the
  # rotate-to-one undo backup on disk indefinitely — exactly the leak
  # the flag is supposed to prevent.
  def test_cleanup_secrets_also_removes_personal_bak_dirs
    Dir.mktmpdir do |tmpdir|
      personal = File.join(tmpdir, "personal")
      FileUtils.mkdir_p(personal)
      File.write(File.join(personal, "gh_token"), "ghp_secret")
      bak = File.join(tmpdir, "personal.bak-20260601-000000")
      FileUtils.mkdir_p(bak)
      File.write(File.join(bak, "gh_token"), "ghp_old_secret")

      runner = MacSetup::Runner.new
      runner.instance_variable_set(:@options, {cleanup_secrets: true})
      runner.define_singleton_method(:decrypted_personal_path) { personal }
      logger = MacSetup::Utils::Logger.new
      capture_io { runner.send(:cleanup_secrets, logger) }

      refute File.exist?(personal), "personal/ must be removed"
      refute File.exist?(bak), "personal.bak-*/ must also be removed"
    end
  end

  def test_cleanup_secrets_keeps_bak_dirs_when_errors_present
    Dir.mktmpdir do |tmpdir|
      personal = File.join(tmpdir, "personal")
      FileUtils.mkdir_p(personal)
      bak = File.join(tmpdir, "personal.bak-20260601-000000")
      FileUtils.mkdir_p(bak)
      File.write(File.join(bak, "gh_token"), "stale_secret")

      runner = MacSetup::Runner.new
      runner.instance_variable_set(:@options, {cleanup_secrets: true})
      runner.define_singleton_method(:decrypted_personal_path) { personal }
      logger = MacSetup::Utils::Logger.new
      capture_io do
        logger.error("simulated module failure")
        runner.send(:cleanup_secrets, logger)
      end

      assert File.directory?(personal), "personal/ preserved on error"
      assert File.directory?(bak), "bak dirs also preserved on error"
    end
  end

  def test_cleanup_secrets_flag_parses_from_argv
    runner = MacSetup::Runner.new(["--cleanup-secrets"])
    assert_equal true, runner.instance_variable_get(:@options)[:cleanup_secrets]
  end

  # acquire_sudo previously used a 50s-keepalive thread to refresh the sudo
  # timestamp. Fragile: silently fails when (a) macOS shortens the default
  # timestamp_timeout, (b) brew/cask scripts call `sudo -k`, or (c) the
  # keepalive thread silently dies. The fix installs a temporary NOPASSWD
  # entry under /etc/sudoers.d (same pattern install-ssh-controller.sh
  # uses on remote targets), removed on exit. Tests assert (a) the file
  # path is pid-uniqued so concurrent runs don't collide, (b) content is
  # exactly NOPASSWD for the current user, (c) prime failure aborts hard
  # instead of silently spamming sudo errors, (d) release is a no-op
  # when nothing was installed (so partial-failure paths don't try to rm
  # a non-existent file).
  def test_sudoers_path_includes_process_pid
    runner = MacSetup::Runner.new
    expected = "/etc/sudoers.d/mac-setup-#{Process.pid}"
    assert_equal expected, runner.send(:sudoers_path)
  end

  def test_sudoers_content_grants_nopasswd_to_current_user
    runner = MacSetup::Runner.new
    runner.define_singleton_method(:current_user) { "alice" }
    assert_equal "alice ALL=(ALL) NOPASSWD: ALL\n", runner.send(:sudoers_content)
  end

  def test_acquire_sudo_aborts_when_prime_password_fails
    runner = MacSetup::Runner.new
    runner.define_singleton_method(:prime_sudo_password) { false }
    # Stub install path too, in case the abort doesn't fire — would surface
    # as a real `sudo tee` invocation in the test, easy to spot.
    runner.define_singleton_method(:write_sudoers_file) { raise "must not be called when prime fails" }
    logger = MacSetup::Utils::Logger.new
    assert_raises(SystemExit) { capture_io { runner.send(:acquire_sudo, logger) } }
  end

  def test_release_sudo_is_no_op_when_nothing_installed
    runner = MacSetup::Runner.new
    # Don't set @sudoers_installed — simulating a partial-failure path
    # where prime succeeded but install bailed before marking installed.
    runner.define_singleton_method(:system) { |*_args| raise "must not call system when nothing installed" }
    runner.send(:release_sudo)
  end

  # Closed-stdin (non-TTY) interactive mode used to silently default to
  # "run every module" because `$stdin.gets` returned nil → answer ""
  # → not "n". On a remote ssh-without-args run that's a surprise: the
  # user expects either a prompt or a clean error, not the whole suite
  # firing unattended. Conservative behavior: abort with a clear hint
  # to pass --all or specific module names.
  def test_select_modules_aborts_when_stdin_is_not_a_tty
    runner = MacSetup::Runner.new
    runner.instance_variable_set(:@options, {})
    runner.instance_variable_set(:@argv, [])
    fake = StringIO.new("")
    def fake.tty?; false; end
    orig = $stdin
    $stdin = fake
    logger = MacSetup::Utils::Logger.new
    capture_io do
      assert_raises(SystemExit) { runner.send(:select_modules, logger) }
    end
  ensure
    $stdin = orig if orig
  end

  def test_select_modules_returns_all_with_all_flag_without_stdin
    runner = MacSetup::Runner.new
    runner.instance_variable_set(:@options, {all: true})
    runner.instance_variable_set(:@argv, [])
    # --all bypasses stdin entirely; even closed stdin works fine.
    selected = runner.send(:select_modules, MacSetup::Utils::Logger.new)
    assert_equal MacSetup::Runner::MODULES, selected
  end

  def test_select_modules_returns_named_modules_without_stdin
    runner = MacSetup::Runner.new
    runner.instance_variable_set(:@options, {})
    runner.instance_variable_set(:@argv, ["homebrew", "secrets"])
    # Named modules also bypass the prompt loop.
    selected = runner.send(:select_modules, MacSetup::Utils::Logger.new)
    assert_includes selected, MacSetup::Homebrew
    assert_includes selected, MacSetup::Secrets
  end

  # Log files accumulate one-per-run forever. The home-server use case
  # means many years of `setup-YYYYMMDD-HHMMSS.log` build up. Prune
  # everything older than the retention window at startup. Keeps the
  # log/ dir self-tidying without losing recent triage history.
  def test_prune_old_logs_removes_files_older_than_retention
    Dir.mktmpdir do |dir|
      old = File.join(dir, "setup-20200101-000000.log")
      recent = File.join(dir, "setup-99991231-235959.log")
      File.write(old, "stale")
      File.write(recent, "fresh")
      File.utime(Time.now - (40 * 86400), Time.now - (40 * 86400), old)
      File.utime(Time.now,                Time.now,                recent)

      runner = MacSetup::Runner.new
      runner.send(:prune_old_logs, dir, days: 30)

      refute File.exist?(old), "older than retention must be pruned"
      assert File.exist?(recent), "recent log must be kept"
    end
  end

  def test_prune_old_logs_only_touches_setup_logs
    Dir.mktmpdir do |dir|
      old_setup = File.join(dir, "setup-20200101-000000.log")
      unrelated_old = File.join(dir, "something_else.log")
      File.write(old_setup, "stale")
      File.write(unrelated_old, "stale-too")
      [old_setup, unrelated_old].each do |p|
        File.utime(Time.now - (90 * 86400), Time.now - (90 * 86400), p)
      end

      runner = MacSetup::Runner.new
      runner.send(:prune_old_logs, dir, days: 30)

      refute File.exist?(old_setup), "setup-*.log: pruned"
      assert File.exist?(unrelated_old), "other files: untouched"
    end
  end

  def test_prune_old_logs_silently_handles_missing_dir
    runner = MacSetup::Runner.new
    runner.send(:prune_old_logs, "/nonexistent/path/that/does/not/exist", days: 30)
    pass
  end
end
