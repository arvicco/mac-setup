# frozen_string_literal: true

require "test_helper"
require "open3"

class TestVersion < Minitest::Test
  # The VERSION constant is the single thing every log file shows; if it
  # drifts from the released tag, triage from a screenshot becomes
  # impossible. These tests guard the chain:
  #   VERSION file on disk → MacSetup::VERSION constant → log header
  def test_version_constant_is_a_nonempty_string
    refute_nil MacSetup::VERSION
    assert_kind_of String, MacSetup::VERSION
    refute_empty MacSetup::VERSION.strip
  end

  def test_version_constant_matches_repo_version_file
    file_path = File.join(MacSetup::ROOT, "VERSION")
    assert File.exist?(file_path), "VERSION file missing at repo root"
    assert_equal File.read(file_path).strip, MacSetup::VERSION
  end

  # Catches "Bob bumped backwards" or "Bob never bumped at all" — the
  # VERSION file must equal the latest tag (just-released, not yet
  # bumped) OR a strictly greater semver (next-release WIP, the normal
  # post-release state). Skips gracefully when no tags are reachable
  # (CI shallow clones, fresh fork without `git fetch --tags`).
  def test_version_file_is_at_or_ahead_of_latest_git_tag
    tag, _, status = Open3.capture3(
      "git", "-C", MacSetup::ROOT, "describe", "--tags", "--abbrev=0"
    )
    skip "no git tags reachable" unless status.success? && !tag.strip.empty?
    tag_v  = tag.strip.sub(/\Av/, "")
    file_v = MacSetup::VERSION
    assert semver_at_least(file_v, tag_v),
           "VERSION (#{file_v}) is behind latest tag (#{tag_v}) — did the release task forget to bump?"
  end

  private

  def semver_at_least(a, b)
    parse = ->(s) { s.split(/[.+-]/).first(3).map { |p| p.to_i } }
    (parse.call(a) <=> parse.call(b)) >= 0
  end
end
