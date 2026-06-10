# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"

class TestGithubAuth < Minitest::Test
  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @mod = MacSetup::GithubAuth.new(
      logger: @logger,
      cmd: MacSetup::Utils::CommandRunner.new(logger: @logger),
    )
  end

  def test_inherits_base_module
    assert MacSetup::GithubAuth < MacSetup::BaseModule
  end

  # No token file ⇒ skip silently. Important: gh_token lives inside
  # config/personal/, which only exists after Secrets runs. Without
  # this guard, every machine without personal config would log a
  # spurious "gh not found" error.
  def test_run_skips_silently_when_no_token_file
    Dir.mktmpdir do |fake_root|
      orig = MacSetup::ROOT
      MacSetup.send(:remove_const, :ROOT)
      MacSetup.const_set(:ROOT, fake_root)
      capture_io { @mod.run }
      assert_match(/No config\/personal\/gh_token/, @log_io.string)
    ensure
      MacSetup.send(:remove_const, :ROOT)
      MacSetup.const_set(:ROOT, orig)
    end
  end
end
