# frozen_string_literal: true

module MacSetup
  class ClaudeCode < BaseModule
    def run
      install_claude_code unless claude_code_installed?
      # Authentication requires browser login — genuinely interactive
      logger.info "To authenticate, run: claude"
    end

    private

    def claude_code_installed?
      cmd.success?("command -v claude")
    end

    def install_claude_code
      logger.info "Installing Claude Code..."
      cmd.run("npm install -g @anthropic-ai/claude-code", abort_on_fail: true)
    end
  end
end
