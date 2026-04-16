# frozen_string_literal: true

require "test_helper"

class TestRunner < Minitest::Test
  def test_modules_list_is_not_empty
    refute_empty MacSetup::Runner::MODULES
  end

  def test_all_modules_inherit_base_module
    MacSetup::Runner::MODULES.each do |mod|
      assert mod < MacSetup::BaseModule, "#{mod} must inherit from BaseModule"
    end
  end

  def test_all_modules_have_a_name
    MacSetup::Runner::MODULES.each do |mod|
      refute_nil mod.module_name
      refute_empty mod.module_name
    end
  end

  # Catches the easy "forgot to add to Runner::MODULES" mistake when a new
  # module file is dropped into lib/mac_setup/.
  def test_every_module_file_is_registered
    module_files = Dir[File.expand_path("../../lib/mac_setup/*.rb", __dir__)]
      .map { |p| File.basename(p, ".rb") }
      .reject { |n| %w[base_module runner].include?(n) }

    registered = MacSetup::Runner::MODULES.map do |mod|
      # e.g. MacSetup::GitConfig -> "git_config"
      mod.name.split("::").last.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    missing = module_files - registered
    assert_empty missing, "These module files are not in Runner::MODULES: #{missing.join(', ')}"
  end
end
