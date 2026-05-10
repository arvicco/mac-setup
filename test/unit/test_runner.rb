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
end
