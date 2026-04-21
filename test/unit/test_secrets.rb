# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class TestSecrets < Minitest::Test
  def setup
    @logger = MacSetup::Utils::Logger.new
    @cmd = MacSetup::Utils::CommandRunner.new(logger: @logger)
    @mod = MacSetup::Secrets.new(logger: @logger, cmd: @cmd)
  end

  def test_inherits_from_base_module
    assert MacSetup::Secrets < MacSetup::BaseModule
  end

  def test_module_name
    assert_equal "Secrets", MacSetup::Secrets.module_name
  end

  def test_encrypted_path_points_to_config_personal_age
    path = @mod.send(:encrypted_path)
    assert path.end_with?("config/personal.age"), "Expected path ending in config/personal.age, got #{path}"
  end

  def test_decrypted_path_points_to_config_personal
    path = @mod.send(:decrypted_path)
    assert path.end_with?("config/personal"), "Expected path ending in config/personal, got #{path}"
  end

  # Priority chain: options[:passphrase] > ENV["AGE_PASSPHRASE"] > prompt.
  # Keep in sync with docs/personal-config.md:141.

  def test_resolve_passphrase_prefers_options_flag_over_env
    with_env("AGE_PASSPHRASE" => "from-env") do
      mod = MacSetup::Secrets.new(logger: @logger, cmd: @cmd, options: { passphrase: "from-flag" })
      assert_equal "from-flag", mod.send(:resolve_passphrase)
    end
  end

  def test_resolve_passphrase_falls_through_to_env_when_no_flag
    with_env("AGE_PASSPHRASE" => "from-env") do
      assert_equal "from-env", @mod.send(:resolve_passphrase)
    end
  end

  def test_resolve_passphrase_falls_through_to_prompt_when_no_flag_no_env
    with_env("AGE_PASSPHRASE" => nil) do
      # Non-TTY in test run → prompt_passphrase returns nil. The important
      # thing is the chain reaches prompt rather than short-circuiting.
      assert_nil @mod.send(:resolve_passphrase)
    end
  end

  def test_resolve_passphrase_empty_flag_does_NOT_mask_env
    # Surprising but established Ruby idiom: `"" || x` returns "" (empty
    # string is truthy). If a user passes --passphrase "" we honor that
    # explicit empty and do not fall through to env. The decrypt caller
    # guards on passphrase.empty? and logs "No passphrase provided".
    with_env("AGE_PASSPHRASE" => "from-env") do
      mod = MacSetup::Secrets.new(logger: @logger, cmd: @cmd, options: { passphrase: "" })
      assert_equal "", mod.send(:resolve_passphrase)
    end
  end

  # Hash-stamp tests: Secrets writes a SHA256 stamp of config/personal.age
  # inside config/personal/ on successful decrypt. up_to_date? uses that
  # stamp to skip re-decrypt on re-runs, and trips automatically when the
  # user pulls a fresher archive (different hash → mismatch → re-decrypt).

  def with_tmp_paths
    Dir.mktmpdir("mac-setup-secrets-") do |root|
      enc = File.join(root, "personal.age")
      dec = File.join(root, "personal")
      # The real age file; contents just need to exist and hash stably.
      File.write(enc, "ciphertext v1")
      @mod.instance_variable_set(:@encrypted_path, enc)
      @mod.instance_variable_set(:@decrypted_path, dec)
      yield enc, dec
    end
  end

  def test_age_source_hash_matches_sha256_of_encrypted_file
    with_tmp_paths do |enc, _|
      require "digest"
      assert_equal Digest::SHA256.file(enc).hexdigest, @mod.send(:age_source_hash)
    end
  end

  def test_up_to_date_false_when_decrypted_dir_absent
    with_tmp_paths do |_, dec|
      refute File.exist?(dec)
      refute @mod.send(:up_to_date?)
    end
  end

  def test_up_to_date_false_when_decrypted_dir_empty
    with_tmp_paths do |_, dec|
      FileUtils.mkdir_p(dec)
      refute @mod.send(:up_to_date?)
    end
  end

  def test_up_to_date_false_when_stamp_missing
    with_tmp_paths do |_, dec|
      FileUtils.mkdir_p(dec)
      File.write(File.join(dec, "git_identity.yml"), "name: foo\n")
      refute @mod.send(:up_to_date?)
    end
  end

  def test_up_to_date_true_when_stamp_matches_current_archive
    with_tmp_paths do |enc, dec|
      FileUtils.mkdir_p(dec)
      File.write(File.join(dec, ".age-source-sha256"), Digest::SHA256.file(enc).hexdigest)
      assert @mod.send(:up_to_date?)
    end
  end

  def test_up_to_date_false_when_stamp_matches_different_archive
    # Simulates "user pulled a newer personal.age" — stamp is from the
    # previous archive, current archive has a different hash → re-decrypt.
    with_tmp_paths do |enc, dec|
      FileUtils.mkdir_p(dec)
      # Stamp from an older (now-overwritten) archive
      File.write(File.join(dec, ".age-source-sha256"), "a" * 64)
      refute @mod.send(:up_to_date?)
      # Sanity — the current archive still produces its own valid hash
      refute_equal "a" * 64, Digest::SHA256.file(enc).hexdigest
    end
  end

  def test_backup_existing_personal_moves_dir_aside
    with_tmp_paths do |_, dec|
      FileUtils.mkdir_p(dec)
      File.write(File.join(dec, "git_identity.yml"), "name: old\n")

      @mod.send(:backup_existing_personal)

      refute File.exist?(dec), "Original decrypted dir should have moved"
      backups = Dir.children(File.dirname(dec)).grep(/\Apersonal\.bak-/)
      assert_equal 1, backups.length
      assert_equal "name: old\n",
                   File.read(File.join(File.dirname(dec), backups.first, "git_identity.yml"))
    end
  end

  def test_backup_existing_personal_noop_when_dir_absent
    with_tmp_paths do |_, dec|
      refute File.exist?(dec)
      # Must not raise and must not create anything
      @mod.send(:backup_existing_personal)
      refute File.exist?(dec)
    end
  end

  def test_backup_existing_personal_noop_when_dir_empty
    with_tmp_paths do |_, dec|
      FileUtils.mkdir_p(dec)
      @mod.send(:backup_existing_personal)
      # Empty dir stays as-is, no backup created
      assert File.directory?(dec)
      assert Dir.empty?(dec)
    end
  end

  def test_backup_existing_personal_returns_path_on_success
    with_tmp_paths do |_, dec|
      FileUtils.mkdir_p(dec)
      File.write(File.join(dec, "x"), "payload")
      path = @mod.send(:backup_existing_personal)
      refute_nil path
      assert File.directory?(path)
      assert path.include?(".bak-"), "expected a .bak- suffix, got #{path}"
    end
  end

  def test_backup_existing_personal_returns_nil_when_no_backup_made
    with_tmp_paths do |_, dec|
      assert_nil @mod.send(:backup_existing_personal)
      FileUtils.mkdir_p(dec)
      assert_nil @mod.send(:backup_existing_personal), "empty dir should not trigger backup"
    end
  end

  def test_note_backup_on_failure_silent_when_no_backup
    # No @backup_path instance var set → nothing to point at → no log line
    @mod.instance_variable_set(:@backup_path, nil)
    out, err = capture_io_streams { @mod.send(:note_backup_on_failure) }
    assert_equal "", out
    assert_equal "", err
  end

  def test_note_backup_on_failure_tells_user_where_backup_is
    @mod.instance_variable_set(:@backup_path, "/Users/x/mac-setup/config/personal.bak-20260101-120000")
    _out, err = capture_io_streams { @mod.send(:note_backup_on_failure) }
    assert_match(/personal\.bak-20260101-120000/, err)
    assert_match(/To restore/, err)
  end

  private

  # Capture stdout+stderr around a block so we can assert on logger output
  # without the noise flooding the test runner's real stdout/stderr.
  def capture_io_streams
    out = StringIO.new
    err = StringIO.new
    orig_out, orig_err = $stdout, $stderr
    $stdout = out
    $stderr = err
    yield
    [out.string, err.string]
  ensure
    $stdout = orig_out
    $stderr = orig_err
  end

  def with_env(vars)
    saved = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
