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

  def test_keys_to_generate_default_is_general_key_only
    mod = MacSetup::Ssh.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
    mod.stub(:github_key_on_disk?, false) do
      keys = mod.keys_to_generate
      assert_equal 1, keys.length
      assert_equal "id_ed25519", keys.first[:file]
    end
  end

  def test_keys_to_generate_with_github_ssh_flag_includes_github_key
    mod = MacSetup::Ssh.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
      options: { github_ssh: true },
    )
    mod.stub(:github_key_on_disk?, false) do
      files = mod.keys_to_generate.map { |k| k[:file] }
      assert_equal %w[id_ed25519 id_ed25519_github], files
      # github key carries a descriptive comment to help identify it on
      # GitHub's Settings → SSH Keys list
      github = mod.keys_to_generate.find { |k| k[:file] == "id_ed25519_github" }
      assert_equal "github", github[:comment]
    end
  end

  # If id_ed25519_github already exists on disk from an earlier run
  # (or was copied in manually), keep managing it even without --github-ssh.
  # Silently ignoring it would disagree with install-ssh-target.sh, which
  # adds it to the keychain based on file presence alone — letting the
  # two code paths diverge is the real bug.
  def test_keys_to_generate_includes_github_when_key_exists_on_disk
    mod = MacSetup::Ssh.new(
      logger: MacSetup::Utils::Logger.new,
      cmd: MacSetup::Utils::CommandRunner.new(logger: MacSetup::Utils::Logger.new),
    )
    mod.stub(:github_key_on_disk?, true) do
      files = mod.keys_to_generate.map { |k| k[:file] }
      assert_equal %w[id_ed25519 id_ed25519_github], files
    end
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
