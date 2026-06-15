# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestTailscale < Minitest::Test
  def setup
    @log_io = StringIO.new
    @logger = MacSetup::Utils::Logger.new(log_file: @log_io)
    @mod = MacSetup::Tailscale.new(
      logger: @logger,
      cmd: MacSetup::Utils::CommandRunner.new(logger: @logger),
    )
  end

  def stub_state(formula:, cask:, config_present: false, orphan: false)
    @mod.define_singleton_method(:formula_installed?) { formula }
    @mod.define_singleton_method(:cask_installed?) { cask }
    # When the cask app is installed, its system extension is loaded too.
    # An "orphan" is the post-uninstall state where the app is gone but the
    # extension persists and keeps filtering traffic.
    @mod.define_singleton_method(:extension_loaded?) { cask || orphan }
    @mod.define_singleton_method(:config_present?) { config_present }
  end

  # capture_io silences stdout/stderr for the block; assertions run
  # against the Logger's log_file buffer (@log_io) instead.
  def silently
    capture_io { yield }
  end

  def test_module_name
    assert_equal "Tailscale", MacSetup::Tailscale.module_name
  end

  def test_inherits_base_module
    assert MacSetup::Tailscale < MacSetup::BaseModule
  end

  def test_build_key_spec_encodes_required_fields
    spec = @mod.send(:build_key_spec, ["tag:home-server"])
    create = spec.dig("capabilities", "devices", "create")
    assert_equal false, create["reusable"]
    assert_equal false, create["ephemeral"]
    assert_equal true,  create["preauthorized"]
    assert_equal ["tag:home-server"], create["tags"]
    assert_operator spec["expirySeconds"], :>, 0
  end

  def test_build_key_spec_passes_multiple_tags_through
    spec = @mod.send(:build_key_spec, ["tag:home-server", "tag:laptop"])
    assert_equal ["tag:home-server", "tag:laptop"], spec.dig("capabilities", "devices", "create", "tags")
  end

  # missing_or_placeholder catches the three "not ready to mint a key"
  # cases: key literally missing from YAML (nil), empty string, and the
  # REPLACE_ME sentinel from the harvester template.
  def test_missing_or_placeholder_detects_nil
    assert_equal ["oauth_client_id"],
                 @mod.missing_or_placeholder("oauth_client_id" => nil, "oauth_client_secret" => "real")
  end

  def test_missing_or_placeholder_detects_empty_string
    assert_equal ["oauth_client_secret"],
                 @mod.missing_or_placeholder("oauth_client_id" => "real", "oauth_client_secret" => "")
  end

  def test_missing_or_placeholder_detects_replace_me_sentinel
    result = @mod.missing_or_placeholder(
      "oauth_client_id" => "REPLACE_ME",
      "oauth_client_secret" => "REPLACE_ME",
    )
    assert_equal ["oauth_client_id", "oauth_client_secret"], result
  end

  def test_missing_or_placeholder_ignores_whitespace_around_replace_me
    result = @mod.missing_or_placeholder("oauth_client_id" => "  REPLACE_ME  ")
    assert_equal ["oauth_client_id"], result
  end

  def test_missing_or_placeholder_passes_real_values_through
    assert_empty @mod.missing_or_placeholder(
      "oauth_client_id" => "tskey-client-abc123",
      "oauth_client_secret" => "tskey-client-secret-xyz",
    )
  end

  # Role detection: the module must not try to set up the headless daemon
  # on a Mac that has the GUI cask installed (and vice versa). Running
  # both simultaneously registers the Mac twice in the tailnet.
  def test_run_errors_when_both_formula_and_cask_are_installed
    stub_state(formula: true, cask: true)
    silently { @mod.run }
    assert_operator @logger.error_count, :>, 0
    assert_match(/Both tailscale formula and tailscale-app cask/, @log_io.string)
    assert_match(/admin console.*noto/, @log_io.string)
  end

  def test_run_skips_headless_setup_when_only_cask_is_installed
    stub_state(formula: false, cask: true)
    silently { @mod.run }
    assert_equal 0, @logger.error_count
    assert_match(/GUI app detected.*[Ss]kipping/, @log_io.string)
  end

  def test_run_warns_when_config_present_but_no_package_installed
    stub_state(formula: false, cask: false, config_present: true)
    silently { @mod.run }
    assert_match(/exists but no tailscale package is installed/, @log_io.string)
  end

  def test_run_silently_skips_when_neither_package_nor_config_present
    stub_state(formula: false, cask: false, config_present: false)
    silently { @mod.run }
    assert_equal 0, @logger.error_count
    assert_match(/No .*tailscale\.yml.*skipping/, @log_io.string)
  end

  # Orphan = cask app uninstalled but its system extension stayed loaded.
  # The extension keeps intercepting host network traffic at the kernel
  # layer (NEPacketTunnelProvider), silently filtering packets to e.g.
  # bridge100, which breaks Tart VMs and other local-bridge users with no
  # surface-level error. The "never both" rule treats orphan-extension as
  # cask-present for conflict detection, AND aborts on a standalone orphan
  # because the filtering happens regardless of whether a daemon manages it.
  def test_run_errors_when_formula_and_orphan_extension_coexist
    stub_state(formula: true, cask: false, orphan: true)
    silently { @mod.run }
    assert_operator @logger.error_count, :>, 0
    assert_match(/orphan/i, @log_io.string)
    assert_match(/system extension/i, @log_io.string)
    refute_match(/install_system_daemon/, @log_io.string,
                 "must abort before any setup work")
  end

  def test_run_errors_on_standalone_orphan_extension_without_formula
    stub_state(formula: false, cask: false, orphan: true)
    silently { @mod.run }
    assert_operator @logger.error_count, :>, 0
    assert_match(/orphan/i, @log_io.string)
  end

  def test_run_treats_cask_app_with_extension_as_normal_install_not_orphan
    # cask: true → both app and extension exist; that's a normal install.
    # Must take the "GUI app detected" path, not the orphan-error path.
    stub_state(formula: false, cask: true)
    silently { @mod.run }
    assert_equal 0, @logger.error_count
    assert_match(/GUI app detected/, @log_io.string)
    refute_match(/orphan/i, @log_io.string)
  end

  # Apple-Silicon only by policy — paths derive from Homebrew::PREFIX.
  # Tailscale used to do runtime prefix detection ("safer wrong answer"
  # fallback); the rest of the codebase always hard-coded /opt/homebrew,
  # so the asymmetry was confusing without buying anything real. If
  # Intel comes back, fix Homebrew::PREFIX once.
  def test_tailscale_bin_resolves_via_homebrew_helper
    assert_equal "/opt/homebrew/bin/tailscale",  @mod.send(:tailscale_bin)
    assert_equal "/opt/homebrew/bin/tailscaled", @mod.send(:tailscaled_bin)
  end

  # extension_loaded? is a best-effort probe: if systemextensionsctl
  # exits non-zero (sandbox quirks, very old macOS, missing binary),
  # the result must be "not loaded" without inflating logger.error_count.
  # The Runner uses error_count to decide whether the module failed —
  # without `quiet: true` on the cmd.run call, every Mac without
  # Tailscale would have its Tailscale module marked as failed.
  def test_extension_loaded_returns_false_and_does_not_record_error_on_probe_failure
    fake_cmd = Object.new
    fake_cmd.define_singleton_method(:run) do |*_args, **_kwargs|
      ["", "boom", Struct.new(:success?, :exitstatus).new(false, 1)]
    end
    @mod.instance_variable_set(:@cmd, fake_cmd)
    refute @mod.send(:extension_loaded?)
    assert_equal 0, @logger.error_count,
                 "probe failure must not bump error_count (would mark module as failed)"
  end

  # BLOCKER fix: when `tailscale up` fails, the captured stderr is
  # forwarded to logger.error via "tailscale up failed: #{err.strip}".
  # If tailscale echoed the offending auth-key back in its validation
  # error, that secret would land in log/setup-*.log unredacted unless
  # we scrub it inline (CommandRunner only scrubs ITS error lines —
  # this `logger.error` is ours). scrub_secrets must turn the tskey-*
  # value into <redacted>.
  def test_scrub_secrets_scrubs_auth_key_value_and_argv_form
    raw = %(failed to authenticate with --auth-key=tskey-MNOXYZ12345; backend rejected)
    scrubbed = @mod.send(:scrub_secrets, raw)
    refute_includes scrubbed, "tskey-MNOXYZ12345"
    refute_includes scrubbed, "tskey-"
    assert_match(/redacted/, scrubbed)
  end

  def test_tailscale_up_failure_path_does_not_leak_secret_to_log
    fake_cmd = Object.new
    fake_cmd.define_singleton_method(:run) do |*_args, **_kwargs|
      ["", "auth failed: tskey-LEAKYVALUE rejected by control",
       Struct.new(:success?, :exitstatus).new(false, 1)]
    end
    @mod.instance_variable_set(:@cmd, fake_cmd)
    assert_raises(RuntimeError) do
      capture_io { @mod.send(:tailscale_up, "tskey-LEAKYVALUE", "host", []) }
    end
    refute_includes @log_io.string, "tskey-LEAKYVALUE",
                    "auth-key value must NOT appear in the log even on failure"
    assert_match(/redacted/, @log_io.string)
  end
end
