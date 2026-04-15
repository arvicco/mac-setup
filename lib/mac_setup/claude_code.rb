# frozen_string_literal: true

module MacSetup
  class ClaudeCode < BaseModule
    def run
      install_claude_code unless claude_code_installed?
      logger.info "Run 'claude' to authenticate and start using Claude Code."
    end

    private

    def claude_code_installed?
      # nvm-managed npm puts binaries under ~/.nvm; source it first
      cmd.success?(nvm_prefix + "command -v claude")
    end

    def install_claude_code
      logger.info "Installing Claude Code..."
      cmd.run(nvm_prefix + "npm install -g @anthropic-ai/claude-code", abort_on_fail: true)
    end

    def nvm_prefix
      'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && '
    end
  end
end
