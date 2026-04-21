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

  # Thin wrapper: invokes the private copy_dotfile with paths derived
  # from a rel path plus our tmp dirs.
  def deploy(rel, source_body)
    src = File.join(@source_dir, rel)
    FileUtils.mkdir_p(File.dirname(src))
    File.write(src, source_body)
    dest = File.join(@home_dir, rel)
    @mod.send(:copy_dotfile, src, dest, rel)
    dest
  end

  def test_module_name
    assert_equal "Shell", MacSetup::Shell.module_name
  end

  def test_copies_when_target_absent
    dest = deploy(".zshrc", "export FOO=bar\n")
    assert File.file?(dest)
    refute File.symlink?(dest)
    assert_equal "export FOO=bar\n", File.read(dest)
  end

  def test_copy_is_a_real_file_not_a_symlink_to_source
    # Regression: removing the source after copy must not break the dotfile.
    dest = deploy(".zshrc", "safe\n")
    FileUtils.remove_entry(@source_dir)
    @source_dir = Dir.mktmpdir("mac-setup-dotfiles-src-replacement-")
    assert_equal "safe\n", File.read(dest)
  end

  def test_is_idempotent_when_content_matches
    dest = deploy(".zshrc", "same\n")
    mtime_before = File.stat(dest).mtime
    sleep 0.01
    deploy(".zshrc", "same\n") # same content, should no-op
    mtime_after = File.stat(dest).mtime
    assert_equal mtime_before, mtime_after
  end

  def test_backs_up_existing_different_plain_file
    dest = File.join(@home_dir, ".zshrc")
    File.write(dest, "old\n")

    deploy(".zshrc", "new\n")

    assert_equal "new\n", File.read(dest)
    backups = Dir.children(@home_dir).grep(/\.zshrc\.bak-/)
    assert_equal 1, backups.length
    assert_equal "old\n", File.read(File.join(@home_dir, backups.first))
  end

  def test_replaces_stale_symlink_from_old_versions
    # Older mac-setup versions symlinked dotfiles. On re-run, convert
    # them to real copies so mac-setup can be removed without breaking.
    target = File.join(@source_dir, ".zshrc")
    File.write(target, "fresh\n")
    dest = File.join(@home_dir, ".zshrc")
    File.symlink(target, dest)

    @mod.send(:copy_dotfile, target, dest, ".zshrc")

    refute File.symlink?(dest)
    assert File.file?(dest)
    assert_equal "fresh\n", File.read(dest)
    backups = Dir.children(@home_dir).grep(/\.zshrc\.bak-/)
    assert_equal 1, backups.length
  end

  def test_creates_nested_parent_directories
    # Harvested path like `.config/nvim/init.lua` must result in the
    # intermediate `~/.config/nvim/` being mkdir_p'd even if the user
    # doesn't have those dirs yet.
    dest = deploy(".config/nvim/init.lua", "-- hi\n")
    assert File.file?(dest)
    assert File.directory?(File.join(@home_dir, ".config", "nvim"))
  end

  def test_merge_semantics_for_nested_tree
    # Pre-seed ~/.config/ with an unrelated app's config. The deploy
    # of a different nested path must not disturb it — the whole point
    # of walking file-by-file.
    unrelated = File.join(@home_dir, ".config", "gh", "hosts.yml")
    FileUtils.mkdir_p(File.dirname(unrelated))
    File.write(unrelated, "gh_config: keep_me\n")

    deploy(".config/git/config", "[user]\n  name = arvicco\n")

    assert_equal "gh_config: keep_me\n", File.read(unrelated)
    assert_equal "[user]\n  name = arvicco\n",
                 File.read(File.join(@home_dir, ".config", "git", "config"))
  end
end
