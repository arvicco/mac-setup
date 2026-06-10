# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"

class TestKarabiner < Minitest::Test
  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @mod = MacSetup::Karabiner.new(
      logger: @logger,
      cmd: MacSetup::Utils::CommandRunner.new(logger: @logger),
    )
  end

  def test_inherits_base_module
    assert MacSetup::Karabiner < MacSetup::BaseModule
  end

  def test_run_warns_when_source_config_is_missing
    # Stub the source path to a non-existent file. Real run resolves it
    # via MacSetup::ROOT — easier to stub the constant lookup.
    MacSetup::Karabiner.stub_const(:CONFIG_SOURCE, "config/does_not_exist.json") do
      capture_io { @mod.run }
    end
    assert_match(/No config\/does_not_exist\.json/, @log_io.string)
  end if MacSetup::Karabiner.respond_to?(:stub_const)

  # Without stub_const helper, exercise the path via the public API:
  # if no source is found the module returns silently — we just want
  # to confirm `run` doesn't raise. (Defends against future
  # NoMethodError regressions in run.)
  def test_run_does_not_raise_on_missing_source
    Dir.mktmpdir do |fake_root|
      orig = MacSetup::ROOT
      MacSetup.send(:remove_const, :ROOT)
      MacSetup.const_set(:ROOT, fake_root)
      capture_io { @mod.run }
    ensure
      MacSetup.send(:remove_const, :ROOT)
      MacSetup.const_set(:ROOT, orig)
    end
  end
end
