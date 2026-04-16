# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestFileEditor < Minitest::Test
  FE = MacSetup::Utils::FileEditor

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "sample.txt")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def test_ensure_line_creates_file_when_absent
    assert FE.ensure_line_in_file(@path, "hello")
    assert_equal "hello\n", File.read(@path)
  end

  def test_ensure_line_is_idempotent
    FE.ensure_line_in_file(@path, "hello")
    refute FE.ensure_line_in_file(@path, "hello")
    assert_equal "hello\n", File.read(@path)
  end

  def test_ensure_line_appends_separator_before_new_content
    File.write(@path, "existing\n")
    assert FE.ensure_line_in_file(@path, "added")
    assert_equal "existing\n\nadded\n", File.read(@path)
  end

  def test_ensure_line_does_not_duplicate_separator
    File.write(@path, "existing\n\n")
    assert FE.ensure_line_in_file(@path, "added")
    assert_equal "existing\n\nadded\n", File.read(@path)
  end

  def test_ensure_block_is_idempotent_via_marker
    block = "# marker-block\nline1\nline2"
    assert FE.ensure_block_in_file(@path, "marker-block", block)
    refute FE.ensure_block_in_file(@path, "marker-block", block)
    assert_equal 1, File.read(@path).scan("marker-block").length
  end
end
