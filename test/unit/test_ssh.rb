# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestSsh < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("mac-setup-ssh-")
    @mod = MacSetup::Ssh.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
  end

  def teardown
    FileUtils.remove_entry(@dir) if File.exist?(@dir)
  end

  def test_module_name
    assert_equal "Ssh", MacSetup::Ssh.module_name
  end

  def test_read_host_lines_drops_blanks
    path = File.join(@dir, "kh")
    File.write(path, "host1 ssh-ed25519 AAA\n\n\nhost2 ssh-ed25519 BBB\n")
    assert_equal ["host1 ssh-ed25519 AAA", "host2 ssh-ed25519 BBB"],
                 @mod.send(:read_host_lines, path)
  end

  def test_read_host_lines_drops_comments
    path = File.join(@dir, "kh")
    File.write(path, "# leading comment\nhost1 ssh-ed25519 AAA\n#trailing\n")
    assert_equal ["host1 ssh-ed25519 AAA"],
                 @mod.send(:read_host_lines, path)
  end

  def test_read_host_lines_rstrips_trailing_whitespace
    path = File.join(@dir, "kh")
    File.write(path, "host1 ssh-ed25519 AAA   \n")
    assert_equal ["host1 ssh-ed25519 AAA"],
                 @mod.send(:read_host_lines, path)
  end

  # The merge itself uses `incoming - existing` to drop dupes. Minimal
  # sanity for the dedup semantics (Array#- preserves order of the
  # operand and drops any element that appears in the subtrahend).
  def test_array_difference_preserves_order_and_dedupes
    existing = ["a", "b"]
    incoming = ["b", "c", "a", "d"]
    assert_equal ["c", "d"], incoming - existing
  end
end
