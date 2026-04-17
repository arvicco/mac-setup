# frozen_string_literal: true

module MacSetup
  class ClaudeCode < BaseModule
    def run
      if claude_code_installed?
        logger.info "Claude Code already installed."
      else
        logger.warn "Claude Code not found — it should have been installed via Brewfile."
        logger.warn "Run: brew install --cask claude-code"
      end
      logger.info "To authenticate, run: claude"
    end

    private

    def claude_code_installed?
      cmd.success?("command -v claude")
    end
  end
end
