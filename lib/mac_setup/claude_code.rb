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

      deployed = 0
      SETTINGS_FILES.each do |name|
        source = File.join(source_dir, name)
        next unless File.exist?(source)
        dest = File.join(CLAUDE_DIR, name)

        if File.exist?(dest) && File.read(dest) == File.read(source)
          logger.info "~/.claude/#{name} already up to date."
          next
        end

        if File.exist?(dest)
          backup = "#{dest}.bak-#{Time.now.strftime("%Y%m%d-%H%M%S")}"
          FileUtils.cp(dest, backup)
          logger.warn "Backed up existing ~/.claude/#{name} to #{File.basename(backup)}"
        end

        FileUtils.mkdir_p(CLAUDE_DIR)
        FileUtils.cp(source, dest)
        logger.success "Installed ~/.claude/#{name}."
        deployed += 1
      end

      logger.info "No Claude Code settings found in #{SETTINGS_SOURCE_DIR}/." if deployed.zero? && SETTINGS_FILES.none? { |n| File.exist?(File.join(source_dir, n)) }
    end
  end
end
