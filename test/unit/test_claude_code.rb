# frozen_string_literal: true

require "test_helper"
require "json"
require "stringio"
require "tmpdir"

class TestClaudeCode < Minitest::Test
  def setup
    @src = Dir.mktmpdir("mac-setup-claude-src-")
    @dest = Dir.mktmpdir("mac-setup-claude-dest-")
    @dotfiles = Dir.mktmpdir("mac-setup-claude-dotfiles-")
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @mod = MacSetup::ClaudeCode.new(
      logger: @logger,
      cmd: MacSetup::Utils::CommandRunner.new(logger: @logger),
    )
  end

  def teardown
    FileUtils.remove_entry(@src)      if File.exist?(@src)
    FileUtils.remove_entry(@dest)     if File.exist?(@dest)
    FileUtils.remove_entry(@dotfiles) if File.exist?(@dotfiles)
  end

  def silently
    result = nil
    capture_io { result = yield }
    result
  end

  def test_module_name
    assert_equal "Claude Code", MacSetup::ClaudeCode.module_name
  end

  def test_inherits_base_module
    assert MacSetup::ClaudeCode < MacSetup::BaseModule
  end

  def test_deploy_setting_file_missing_source_returns_missing
    result = @mod.send(:deploy_setting_file, @src, @dest, "settings.json")
    assert_equal :missing, result
    refute File.exist?(File.join(@dest, "settings.json"))
  end

  def test_deploy_setting_file_installs_when_dest_absent
    File.write(File.join(@src, "settings.json"), %({"theme":"dark"}))
    result = @mod.send(:deploy_setting_file, @src, @dest, "settings.json")
    assert_equal :installed, result
    assert_equal %({"theme":"dark"}), File.read(File.join(@dest, "settings.json"))
  end

  def test_deploy_setting_file_unchanged_when_bytes_match
    File.write(File.join(@src,  "settings.json"), %({"x":1}))
    File.write(File.join(@dest, "settings.json"), %({"x":1}))
    mtime_before = File.stat(File.join(@dest, "settings.json")).mtime
    sleep 0.01
    result = @mod.send(:deploy_setting_file, @src, @dest, "settings.json")
    mtime_after = File.stat(File.join(@dest, "settings.json")).mtime
    assert_equal :unchanged, result
    assert_equal mtime_before, mtime_after
  end

  def test_deploy_setting_file_backs_up_differing_dest
    File.write(File.join(@src,  "settings.json"), %({"x":"new"}))
    File.write(File.join(@dest, "settings.json"), %({"x":"old"}))

    result = @mod.send(:deploy_setting_file, @src, @dest, "settings.json")

    assert_equal :updated, result
    assert_equal %({"x":"new"}), File.read(File.join(@dest, "settings.json"))
    backups = Dir.children(@dest).grep(/settings\.json\.bak-/)
    assert_equal 1, backups.length
    assert_equal %({"x":"old"}), File.read(File.join(@dest, backups.first))
  end

  def test_deploy_setting_file_creates_dest_dir_if_missing
    nested = File.join(@dest, "nested")
    File.write(File.join(@src, "settings.json"), %({}))
    result = @mod.send(:deploy_setting_file, @src, nested, "settings.json")
    assert_equal :installed, result
    assert File.directory?(nested)
    assert File.exist?(File.join(nested, "settings.json"))
  end

  # ---- link_hooks_dir ---------------------------------------------------

  def test_link_hooks_creates_symlink_when_target_absent
    hooks_src = File.join(@dotfiles, "hooks")
    FileUtils.mkdir_p(hooks_src)

    result = silently { @mod.send(:link_hooks_dir, @dotfiles, @dest) }

    link = File.join(@dest, "hooks")
    assert_equal :linked, result
    assert File.symlink?(link)
    assert_equal hooks_src, File.readlink(link)
  end

  def test_link_hooks_replaces_existing_symlink
    hooks_src = File.join(@dotfiles, "hooks")
    FileUtils.mkdir_p(hooks_src)
    old_target = Dir.mktmpdir("mac-setup-claude-old-")
    File.symlink(old_target, File.join(@dest, "hooks"))

    result = silently { @mod.send(:link_hooks_dir, @dotfiles, @dest) }

    assert_equal :linked, result
    assert_equal hooks_src, File.readlink(File.join(@dest, "hooks"))
  ensure
    FileUtils.remove_entry(old_target) if old_target && File.exist?(old_target)
  end

  def test_link_hooks_errors_and_skips_when_real_directory_present
    hooks_src = File.join(@dotfiles, "hooks")
    FileUtils.mkdir_p(hooks_src)
    real = File.join(@dest, "hooks")
    FileUtils.mkdir_p(real)
    File.write(File.join(real, "user-data.sh"), "#!/bin/sh\n")

    result = silently { @mod.send(:link_hooks_dir, @dotfiles, @dest) }

    assert_equal :skipped, result
    refute File.symlink?(real)
    assert File.exist?(File.join(real, "user-data.sh")), "must not clobber real dir"
    assert_operator @logger.error_count, :>, 0
  end

  def test_link_hooks_skips_when_dotfiles_hooks_dir_missing
    # @dotfiles exists but no hooks/ subdir
    result = silently { @mod.send(:link_hooks_dir, @dotfiles, @dest) }
    assert_equal :missing, result
    refute File.exist?(File.join(@dest, "hooks"))
  end

  # ---- merge_snippet_hooks ---------------------------------------------

  def write_snippet(hooks)
    path = File.join(@dotfiles, "settings.snippet.json")
    File.write(path, JSON.generate("hooks" => hooks))
    path
  end

  def stop_hook(cmd)
    { "matcher" => "", "hooks" => [{ "type" => "command", "command" => cmd }] }
  end

  def test_merge_snippet_returns_missing_when_snippet_absent
    result = silently do
      @mod.send(:merge_snippet_hooks,
                File.join(@dotfiles, "no.json"),
                File.join(@dest, "settings.json"))
    end
    assert_equal :missing, result
  end

  def test_merge_snippet_creates_settings_when_absent
    snippet = write_snippet("Stop" => [stop_hook("x.sh")])
    settings = File.join(@dest, "settings.json")

    result = silently { @mod.send(:merge_snippet_hooks, snippet, settings) }

    assert_equal :merged, result
    data = JSON.parse(File.read(settings))
    assert_equal 1, data.dig("hooks", "Stop").length
    assert_equal "x.sh", data.dig("hooks", "Stop", 0, "hooks", 0, "command")
  end

  def test_merge_snippet_appends_per_event_arrays_preserving_existing
    snippet = write_snippet(
      "UserPromptSubmit" => [stop_hook("new.sh")],
    )
    settings = File.join(@dest, "settings.json")
    File.write(settings, JSON.generate(
      "permissions" => { "allow" => ["Bash(ls)"] },
      "hooks" => { "Notification" => [stop_hook("old.sh")] },
    ))

    silently { @mod.send(:merge_snippet_hooks, snippet, settings) }

    data = JSON.parse(File.read(settings))
    assert_equal ["Bash(ls)"], data.dig("permissions", "allow")
    assert_equal 1, data.dig("hooks", "Notification").length
    assert_equal "old.sh", data.dig("hooks", "Notification", 0, "hooks", 0, "command")
    assert_equal 1, data.dig("hooks", "UserPromptSubmit").length
    assert_equal "new.sh", data.dig("hooks", "UserPromptSubmit", 0, "hooks", 0, "command")
  end

  def test_merge_snippet_backs_up_before_mutating
    snippet = write_snippet("Stop" => [stop_hook("x.sh")])
    settings = File.join(@dest, "settings.json")
    File.write(settings, JSON.generate("hooks" => {}))

    silently { @mod.send(:merge_snippet_hooks, snippet, settings) }

    backups = Dir.children(@dest).grep(/\Asettings\.json\.bak-/)
    assert_equal 1, backups.length, "expected exactly one backup"
    backup_data = JSON.parse(File.read(File.join(@dest, backups.first)))
    assert_equal({}, backup_data["hooks"], "backup must capture pre-merge state")
  end

  def test_merge_snippet_idempotent_on_rerun
    snippet = write_snippet("Stop" => [stop_hook("x.sh")])
    settings = File.join(@dest, "settings.json")
    File.write(settings, JSON.generate({})) # preexisting; first merge will back up

    silently { @mod.send(:merge_snippet_hooks, snippet, settings) }
    second = silently { @mod.send(:merge_snippet_hooks, snippet, settings) }

    assert_equal :unchanged, second
    data = JSON.parse(File.read(settings))
    assert_equal 1, data.dig("hooks", "Stop").length, "no duplicate hook entries on re-run"
    backups = Dir.children(@dest).grep(/\Asettings\.json\.bak-/)
    assert_equal 1, backups.length, "exactly one backup (from first merge); no-op re-run does not back up"
  end
end
