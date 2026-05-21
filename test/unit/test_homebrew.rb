# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"

class TestHomebrew < Minitest::Test
  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    cmd = Object.new
    cmd.define_singleton_method(:run) do |*_args, **_kwargs|
      ["", "", Struct.new(:success?, :exitstatus).new(true, 0)]
    end
    @mod = MacSetup::Homebrew.new(logger: @logger, cmd: cmd)
  end

  def test_module_name
    assert_equal "Homebrew", MacSetup::Homebrew.module_name
  end

  def test_inherits_base_module
    assert MacSetup::Homebrew < MacSetup::BaseModule
  end

  # Brew's `ruby` formula is keg-only: brew won't symlink it into
  # /opt/homebrew/bin because macOS ships ruby at /usr/bin/ruby.
  # `brew shellenv` doesn't add the keg path to PATH either, so without
  # an explicit export `ruby`, `gem`, `bundle`, `irb` etc. all keep
  # resolving to Apple's deprecated stock 2.6.10. configure_path must
  # write the keg-only export to ~/.zprofile (future shells) AND prepend
  # to the current process's ENV["PATH"] (subsequent modules in the
  # same bin/setup run).
  def test_configure_path_writes_keg_only_ruby_export_to_zprofile
    Dir.mktmpdir do |tmpdir|
      with_home(tmpdir) do
        capture_io { @mod.send(:configure_path) }
        content = File.read(File.join(tmpdir, ".zprofile"))
        assert_match(%r{export PATH="/opt/homebrew/opt/ruby/bin:\$PATH"}, content)
      end
    end
  end

  def test_configure_path_keg_only_ruby_zprofile_line_is_idempotent
    Dir.mktmpdir do |tmpdir|
      with_home(tmpdir) do
        capture_io { @mod.send(:configure_path) }
        capture_io { @mod.send(:configure_path) }
        content = File.read(File.join(tmpdir, ".zprofile"))
        occurrences = content.scan(%r{export PATH="/opt/homebrew/opt/ruby/bin}).size
        assert_equal 1, occurrences,
                     "keg-only ruby export must appear exactly once after two runs"
      end
    end
  end

  def test_configure_path_prepends_keg_only_ruby_to_current_env_path
    Dir.mktmpdir do |tmpdir|
      with_home(tmpdir) do
        original_path = ENV["PATH"]
        # Strip any pre-existing keg-only ruby so we can verify it gets added.
        ENV["PATH"] = original_path.split(":").reject { |p| p == "/opt/homebrew/opt/ruby/bin" }.join(":")
        begin
          capture_io { @mod.send(:configure_path) }
          ruby_idx    = ENV["PATH"].index("/opt/homebrew/opt/ruby/bin")
          usr_bin_idx = ENV["PATH"].index("/usr/bin")
          refute_nil ruby_idx, "keg-only ruby must be on PATH after configure_path"
          if usr_bin_idx
            assert ruby_idx < usr_bin_idx,
                   "keg-only ruby (idx #{ruby_idx}) must precede /usr/bin (idx #{usr_bin_idx}) so it wins lookup"
          end
        ensure
          ENV["PATH"] = original_path
        end
      end
    end
  end

  private

  def with_home(tmpdir)
    original_home = ENV["HOME"]
    ENV["HOME"] = tmpdir
    yield
  ensure
    ENV["HOME"] = original_home
  end
end
