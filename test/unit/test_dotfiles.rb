# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"
require "yaml"

class TestDotfiles < Minitest::Test
  REPO_URL = "https://example.com/u/dotfiles.git"

  class FakeStatus
    def initialize(success); @success = success; end
    def success?; @success; end
    def exitstatus; @success ? 0 : 1; end
  end

  class FakeCmd
    attr_reader :calls

    def initialize(success: true)
      @calls = []
      @success = success
    end

    def run(*args, **opts)
      @calls << { args: args, opts: opts }
      ["", "", FakeStatus.new(@success)]
    end

    def success?(*args)
      @calls << { args: args, opts: { success_check: true } }
      @success
    end
  end

  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @cmd = FakeCmd.new
    @mod = MacSetup::Dotfiles.new(logger: @logger, cmd: @cmd)

    @config_path = Tempfile.new(["dotfiles", ".yml"]).tap(&:close).path
    File.unlink(@config_path)
    @target = Dir.mktmpdir("mac-setup-dotfiles-target-")
    FileUtils.rm_rf(@target) # default: target absent

    config_path = @config_path
    target = @target
    @mod.define_singleton_method(:config_path)   { config_path }
    @mod.define_singleton_method(:dotfiles_path) { target }
  end

  def teardown
    File.unlink(@config_path) if File.exist?(@config_path)
    FileUtils.remove_entry(@target) if File.exist?(@target)
  end

  def silently
    capture_io { yield }
  end

  def write_config(repo: REPO_URL)
    data = repo.nil? ? {} : { "repo" => repo }
    File.write(@config_path, data.to_yaml)
  end

  def git_init(dir)
    FileUtils.mkdir_p(dir)
    out, err, status = Open3.capture3("git", "-C", dir, "init", "-q")
    raise "git init failed: #{err}" unless status.success?
    out
  end

  def test_module_name
    assert_equal "Dotfiles", MacSetup::Dotfiles.module_name
  end

  def test_inherits_base_module
    assert MacSetup::Dotfiles < MacSetup::BaseModule
  end

  def test_run_skips_when_config_yaml_absent
    # @config_path intentionally does not exist
    silently { @mod.run }
    assert_empty @cmd.calls
    assert_equal 0, @logger.error_count
    assert_match(/skipping/i, @log_io.string)
  end

  def test_run_errors_when_config_yaml_missing_repo_key
    write_config(repo: nil)
    silently { @mod.run }
    assert_empty @cmd.calls
    assert_operator @logger.error_count, :>, 0
    assert_match(/repo/i, @log_io.string)
  end

  def test_run_clones_when_dotfiles_absent
    write_config
    silently { @mod.run }
    refute_empty @cmd.calls, "expected at least one cmd invocation"
    last = @cmd.calls.last
    assert_equal "git", last[:args][0]
    assert_equal "clone", last[:args][1]
    assert_includes last[:args], REPO_URL
    assert_includes last[:args], @target
  end

  def test_run_pulls_when_dotfiles_repo_present
    write_config
    git_init(@target)
    silently { @mod.run }
    refute_empty @cmd.calls
    last = @cmd.calls.last
    assert_equal "git", last[:args][0]
    assert_includes last[:args], "-C"
    assert_includes last[:args], @target
    assert_includes last[:args], "pull"
    assert_includes last[:args], "--ff-only"
  end

  def test_run_errors_when_path_exists_but_not_a_git_repo
    write_config
    FileUtils.mkdir_p(@target)
    File.write(File.join(@target, "stranger.txt"), "hello")
    silently { @mod.run }
    assert_empty @cmd.calls, "must not run git when path is not a repo"
    assert_operator @logger.error_count, :>, 0
    assert File.exist?(File.join(@target, "stranger.txt")), "must not clobber existing files"
  end
end
