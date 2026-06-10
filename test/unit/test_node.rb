# frozen_string_literal: true

require "test_helper"

class TestNode < Minitest::Test
  def test_inherits_base_module
    assert MacSetup::Node < MacSetup::BaseModule
  end

  def test_nvm_version_is_pinned
    # We pin nvm so a head-fetch surprise (deleted tag, breaking install
    # script) doesn't take down every fresh install. Bump deliberately,
    # don't track HEAD.
    assert_kind_of String, MacSetup::Node::NVM_VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, MacSetup::Node::NVM_VERSION)
  end

  def test_nvm_dir_resolves_under_home
    assert_equal File.expand_path("~/.nvm"), MacSetup::Node::NVM_DIR
  end
end
