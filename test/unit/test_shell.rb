# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestShell < Minitest::Test
  def setup
    @original_home = ENV["HOME"]
    @source_dir = Dir.mktmpdir("mac-setup-dotfiles-src-")
    @home_dir   = Dir.mktmpdir("mac-setup-dotfiles-home-")
    ENV["HOME"] = @home_dir
    @mod = MacSetup::Shell.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
  end

  def teardown
    ENV["HOME"] = @original_home
    FileUtils.remove_entry(@source_dir) if File.exist?(@source_dir)
    FileUtils.remove_entry(@home_dir)   if File.exist?(@home_dir)
  end

  def test_module_name
    assert_equal "Shell", MacSetup::Shell.module_name
  end

  def test_copy_dotfile_copies_when_target_absent
    src = File.join(@source_dir, ".zshrc")
    File.write(src, "export FOO=bar\n")
    @mod.send(:copy_dotfile, @source_dir, ".zshrc")
    dest = File.join(@home_dir, ".zshrc")
    assert File.file?(dest)
    refute File.symlink?(dest)
    assert_equal "export FOO=bar\n", File.read(dest)
  end

  def test_copy_dotfile_removes_mac_setup_doesnt_break_dotfile
    # Regression test for the symlink bug: after copy, deleting the source
    # should leave the dotfile in place and readable.
    src = File.join(@source_dir, ".zshrc")
    File.write(src, "safe\n")
    @mod.send(:copy_dotfile, @source_dir, ".zshrc")
    FileUtils.remove_entry(@source_dir)
    @source_dir = Dir.mktmpdir("mac-setup-dotfiles-src-replacement-") # for teardown
    assert_equal "safe\n", File.read(File.join(@home_dir, ".zshrc"))
  end

  def test_copy_dotfile_is_idempotent_when_content_matches
    src = File.join(@source_dir, ".zshrc")
    File.write(src, "same\n")
    @mod.send(:copy_dotfile, @source_dir, ".zshrc")
    mtime_before = File.stat(File.join(@home_dir, ".zshrc")).mtime
    sleep 0.01
    @mod.send(:copy_dotfile, @source_dir, ".zshrc")
    mtime_after = File.stat(File.join(@home_dir, ".zshrc")).mtime
    assert_equal mtime_before, mtime_after
  end

  def test_copy_dotfile_backs_up_existing_different_plain_file
    src = File.join(@source_dir, ".zshrc")
    File.write(src, "new\n")
    dest = File.join(@home_dir, ".zshrc")
    File.write(dest, "old\n")

    @mod.send(:copy_dotfile, @source_dir, ".zshrc")

    assert_equal "new\n", File.read(dest)
    backups = Dir.children(@home_dir).grep(/\.zshrc\.bak-/)
    assert_equal 1, backups.length
    assert_equal "old\n", File.read(File.join(@home_dir, backups.first))
  end

  def test_copy_dotfile_replaces_stale_symlink_from_old_versions
    # Older mac-setup versions used symlinks. On re-run, convert them
    # to a copy so mac-setup can be removed without breaking anything.
    File.write(File.join(@source_dir, ".zshrc"), "fresh\n")
    target = File.join(@source_dir, ".zshrc")
    dest = File.join(@home_dir, ".zshrc")
    File.symlink(target, dest)

    @mod.send(:copy_dotfile, @source_dir, ".zshrc")

    refute File.symlink?(dest)
    assert File.file?(dest)
    assert_equal "fresh\n", File.read(dest)
    backups = Dir.children(@home_dir).grep(/\.zshrc\.bak-/)
    assert_equal 1, backups.length
  end
end
