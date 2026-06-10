# frozen_string_literal: true

require "test_helper"

class TestDefaultBrowser < Minitest::Test
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
    @mod = MacSetup::DefaultBrowser.new(logger: @logger, cmd: @cmd)
  end

  def test_inherits_base_module
    assert MacSetup::DefaultBrowser < MacSetup::BaseModule
  end

  def test_defaultbrowser_path_uses_homebrew_helper
    assert_equal "/opt/homebrew/bin/defaultbrowser", MacSetup::DefaultBrowser::DEFAULTBROWSER
  end

  # On CI / dev boxes without Chrome.app installed, the module should
  # warn-and-return rather than exec defaultbrowser with no target.
  # File.exist? on /Applications/Google Chrome.app is the gate; in the
  # test env it should be false (CI macos-latest doesn't preinstall Chrome).
  def test_run_skips_when_chrome_not_installed
    skip "test box has Chrome installed; cannot exercise skip path" if File.exist?("/Applications/Google Chrome.app")
    capture_io { @mod.run }
    assert_empty @cmd_calls
    assert_match(/Google Chrome not found/, @log_io.string)
  end
end
