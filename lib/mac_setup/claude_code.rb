# frozen_string_literal: true

require "fileutils"

module MacSetup
  class ClaudeCode < BaseModule
    SETTINGS_SOURCE_DIR = File.join("config", "personal", "claude")
    CLAUDE_DIR = File.expand_path("~/.claude")
    # Files we deploy from config/personal/claude/ into ~/.claude/.
    # settings.json is the shared, checked-in config; settings.local.json
    # is per-machine overrides (often harvested as a convenience but may
    # or may not exist).
    SETTINGS_FILES = %w[settings.json settings.local.json].freeze

    def run
      if claude_code_installed?
        logger.info "Claude Code already installed."
      else
        logger.warn "Claude Code not found — it should have been installed via Brewfile."
        logger.warn "Run: brew install --cask claude-code"
      end
      deploy_settings
      logger.info "To authenticate, run: claude"
    end

    private

    def claude_code_installed?
      cmd.success?("command -v claude")
    end

    def deploy_settings
      source_dir = File.join(MacSetup::ROOT, SETTINGS_SOURCE_DIR)
      return unless File.directory?(source_dir)

      any_source = SETTINGS_FILES.any? { |n| File.exist?(File.join(source_dir, n)) }
      unless any_source
        logger.info "No Claude Code settings found in #{SETTINGS_SOURCE_DIR}/."
        return
      end
      SETTINGS_FILES.each { |name| deploy_setting_file(source_dir, CLAUDE_DIR, name) }
    end

    # Returns :installed / :updated / :unchanged / :missing.
    def deploy_setting_file(source_dir, dest_dir, name)
      source = File.join(source_dir, name)
      return :missing unless File.exist?(source)
      dest = File.join(dest_dir, name)

      if File.exist?(dest) && File.read(dest) == File.read(source)
        logger.info "#{dest} already up to date."
        return :unchanged
      end

      result = :installed
      if File.exist?(dest)
        backup = "#{dest}.bak-#{Time.now.strftime("%Y%m%d-%H%M%S")}"
        FileUtils.cp(dest, backup)
        logger.warn "Backed up existing #{dest} to #{File.basename(backup)}"
        result = :updated
      end

      FileUtils.mkdir_p(dest_dir)
      FileUtils.cp(source, dest)
      logger.success "Installed #{dest}."
      result
    end
  end
end
