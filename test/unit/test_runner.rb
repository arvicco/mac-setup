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
end
