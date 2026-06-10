# frozen_string_literal: true

require "test_helper"

# SudoSession previously lived inline in Runner as a half-dozen private
# methods. The class wraps the same NOPASSWD-via-sudoers.d pattern with
# its own seam for testing: pid-uniqued path, exact NOPASSWD content,
# prime-failure aborts hard, release is a no-op when nothing installed.
#
# The original 50s-keepalive-thread design silently failed on long brew
# runs (macOS shortened timestamp_timeout, brew/cask called `sudo -k`,
# the keepalive thread died) — these tests are the regression net for
# that bug class.
class TestSudoSession < Minitest::Test
  def setup
    @logger = MacSetup::Utils::Logger.new
    @session = MacSetup::SudoSession.new(logger: @logger)
  end

  def test_sudoers_path_includes_process_pid
    expected = "/etc/sudoers.d/mac-setup-#{Process.pid}"
    assert_equal expected, @session.sudoers_path
  end

  def test_sudoers_content_grants_nopasswd_to_current_user
    @session.define_singleton_method(:current_user) { "alice" }
    assert_equal "alice ALL=(ALL) NOPASSWD: ALL\n", @session.sudoers_content
  end

  def test_acquire_aborts_when_prime_password_fails
    @session.define_singleton_method(:prime_sudo_password) { false }
    @session.define_singleton_method(:write_sudoers_file) { raise "must not be called when prime fails" }
    assert_raises(SystemExit) { capture_io { @session.acquire } }
  end

  def test_release_is_no_op_when_nothing_installed
    # @sudoers_installed is false by construction.
    @session.define_singleton_method(:system) { |*_args| raise "must not call system when nothing installed" }
    @session.release
  end
end
