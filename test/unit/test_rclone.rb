# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"

class TestRclone < Minitest::Test
  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @mod = MacSetup::Rclone.new(
      logger: @logger,
      cmd: MacSetup::Utils::CommandRunner.new(logger: @logger),
    )
  end

  def test_inherits_base_module
    assert MacSetup::Rclone < MacSetup::BaseModule
  end

  # rclone.conf carries OAuth tokens for every cloud remote — rclone
  # itself refuses to load it without 0600 perms. The module exists
  # primarily to do that one chmod after copying.
  def test_run_skips_silently_when_no_source
    Dir.mktmpdir do |fake_root|
      orig = MacSetup::ROOT
      MacSetup.send(:remove_const, :ROOT)
      MacSetup.const_set(:ROOT, fake_root)
      capture_io { @mod.run }
      assert_match(/skipping rclone config/, @log_io.string)
    ensure
      MacSetup.send(:remove_const, :ROOT)
      MacSetup.const_set(:ROOT, orig)
    end
  end
end
