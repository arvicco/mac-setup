# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class TestHarvester < Minitest::Test
  def setup
    @h = MacSetup::Harvester.new
  end

  # coerce_value translates `defaults read` stdout into the YAML value
  # we emit to macos_defaults_discovered.yml. `defaults read` prints
  # booleans as "1"/"0" (and sometimes "true"/"false") and numbers as
  # base-10 strings.

  def test_coerce_bool_truthy_forms
    %w[1 true TRUE True].each do |raw|
      assert_equal true, @h.send(:coerce_value, raw, "bool"), "expected #{raw.inspect} → true"
    end
  end

  def test_coerce_bool_falsy_forms
    ["0", "false", "False", "FALSE", "", "anything-else"].each do |raw|
      assert_equal false, @h.send(:coerce_value, raw, "bool"), "expected #{raw.inspect} → false"
    end
  end

  def test_coerce_int
    assert_equal 42, @h.send(:coerce_value, "42", "int")
    assert_equal(-7, @h.send(:coerce_value, "-7", "int"))
    # `defaults read` would never return this, but the coercion should
    # still behave (String#to_i parses the numeric prefix).
    assert_equal 12, @h.send(:coerce_value, "12 garbage", "int")
    assert_equal 0, @h.send(:coerce_value, "not-a-number", "int")
  end

  def test_coerce_float
    assert_in_delta 2.5, @h.send(:coerce_value, "2.5", "float"), 0.001
    assert_in_delta 0.0, @h.send(:coerce_value, "0", "float"), 0.001
  end

  def test_coerce_string_passes_raw_through
    assert_equal "Dark", @h.send(:coerce_value, "Dark", "string")
    assert_equal "right", @h.send(:coerce_value, "right", "string")
  end

  def test_coerce_unknown_type_passes_raw_through
    # Defensive: any type we haven't enumerated returns the raw string
    # rather than raising. New types can be added to the YAML format
    # without breaking the harvester.
    assert_equal "whatever", @h.send(:coerce_value, "whatever", "array-of-strings")
  end

  # .DS_Store files are macOS Finder metadata and have no business
  # traveling inside the encrypted personal archive. Without this
  # filter, every harvested dotdir picks up the user's Finder cruft
  # and the tarball grows for no reason on every re-harvest.
  def test_copy_dotdir_skips_DS_Store
    Dir.mktmpdir do |dir|
      src = File.join(dir, "src")
      FileUtils.mkdir_p(src)
      File.write(File.join(src, ".DS_Store"), "binary-cruft")
      File.write(File.join(src, "real_file"), "useful")
      out_dir = File.join(dir, "out")

      @h.instance_variable_set(:@output_dir, out_dir)
      @h.send(:copy_dotdir_tree, src, "dotfiles/.config/x")

      assert File.exist?(File.join(out_dir, "dotfiles/.config/x/real_file"))
      refute File.exist?(File.join(out_dir, "dotfiles/.config/x/.DS_Store")),
             ".DS_Store must NOT be copied into the harvest"
    end
  end

  # stow / chezmoi setups frequently have ~/.config/nvim → ~/dotfiles/nvim
  # as a symlink-to-directory. Following it would (a) silently drop the
  # linked content (Dir.glob doesn't descend through symlinks), and (b)
  # pull out-of-tree files into the encrypted archive. Preserve the link.
  def test_copy_dotdir_preserves_symlinks_to_directories
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target")
      FileUtils.mkdir_p(target)
      File.write(File.join(target, "real"), "content")
      src = File.join(dir, "src")
      FileUtils.mkdir_p(src)
      File.symlink(target, File.join(src, "linked_dir"))
      out_dir = File.join(dir, "out")

      @h.instance_variable_set(:@output_dir, out_dir)
      @h.send(:copy_dotdir_tree, src, "dotfiles/.config/x")

      link_dest = File.join(out_dir, "dotfiles/.config/x/linked_dir")
      assert File.symlink?(link_dest), "symlink-to-dir must be preserved as a symlink"
      assert_equal target, File.readlink(link_dest)
    end
  end

  def test_copy_dotdir_preserves_symlinks_to_files
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target_file")
      File.write(target, "real content")
      src = File.join(dir, "src")
      FileUtils.mkdir_p(src)
      File.symlink(target, File.join(src, "linked_file"))
      out_dir = File.join(dir, "out")

      @h.instance_variable_set(:@output_dir, out_dir)
      @h.send(:copy_dotdir_tree, src, "dotfiles/.config/x")

      link_dest = File.join(out_dir, "dotfiles/.config/x/linked_file")
      assert File.symlink?(link_dest), "symlink-to-file must be preserved as a symlink"
      assert_equal target, File.readlink(link_dest)
    end
  end
end
