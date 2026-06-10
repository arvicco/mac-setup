# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"

class TestIterm2 < Minitest::Test
  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @mod = MacSetup::Iterm2.new(
      logger: @logger,
      cmd: MacSetup::Utils::CommandRunner.new(logger: @logger),
    )
  end

  def test_inherits_base_module
    assert MacSetup::Iterm2 < MacSetup::BaseModule
  end

  # No source file ⇒ skip silently. Important: the iTerm2 plist is in
  # config/personal/, which only exists after Secrets runs; if it's
  # absent we don't want to error, just leave the user's prefs alone.
  def test_run_skips_when_source_plist_absent
    Dir.mktmpdir do |fake_root|
      orig = MacSetup::ROOT
      MacSetup.send(:remove_const, :ROOT)
      MacSetup.const_set(:ROOT, fake_root)
      capture_io { @mod.run }
      assert_match(/skipping iTerm2/, @log_io.string)
    ensure
      MacSetup.send(:remove_const, :ROOT)
      MacSetup.const_set(:ROOT, orig)
    end
  end
end
