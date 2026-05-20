# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"

class TestHomebrewPersonal < Minitest::Test
  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @cmd_calls = []
    recorder = @cmd_calls
    cmd = Object.new
    cmd.define_singleton_method(:run) do |*args, **kwargs|
      recorder << {args: args, kwargs: kwargs}
      ["", "", Struct.new(:success?, :exitstatus).new(true, 0)]
    end
    @cmd = cmd
    @mod = MacSetup::HomebrewPersonal.new(logger: @logger, cmd: @cmd)
  end

  def test_inherits_base_module
    assert MacSetup::HomebrewPersonal < MacSetup::BaseModule
  end

  # Personal Brewfile lives inside the encrypted personal.age archive.
  # On a Mac where Secrets module decided to skip (no .age file, wrong
  # passphrase, etc.) the directory won't exist — this module must no-op
  # rather than failing the run.
  def test_skips_silently_when_personal_brewfile_missing
    nonexistent = "/tmp/mac-setup-test-no-such-#{Process.pid}/Brewfile"
    @mod.define_singleton_method(:personal_brewfile_path) { nonexistent }
    capture_io { @mod.run }
    assert_empty @cmd_calls, "must not invoke brew bundle when personal Brewfile is missing"
    assert_match(/[Ss]kipping/, @log_io.string)
  end

  def test_invokes_brew_bundle_with_personal_brewfile_path_when_present
    Dir.mktmpdir do |tmpdir|
      personal = File.join(tmpdir, "Brewfile")
      File.write(personal, "brew \"jq\"\n")
      @mod.define_singleton_method(:personal_brewfile_path) { personal }
      capture_io { @mod.run }

      assert_equal 1, @cmd_calls.size
      args = @cmd_calls.first[:args].flatten
      assert_includes args, "bundle"
      assert_includes args, "--file=#{personal}"
    end
  end
end
