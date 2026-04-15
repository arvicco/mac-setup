# frozen_string_literal: true

module MacSetup
  class GitConfig < BaseModule
    def run
      # TODO: Customize these values
      set_config "user.name", "Your Name"
      set_config "user.email", "you@example.com"
      set_config "init.defaultBranch", "main"
      set_config "pull.rebase", "true"
      set_config "core.editor", "vim"
    end

    private

    def set_config(key, value)
      logger.info "git config --global #{key} #{value}"
      cmd.run("git config --global #{key} \"#{value}\"")
    end
  end
end
