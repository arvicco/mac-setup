# frozen_string_literal: true

module MacSetup
  class Shell < BaseModule
    def run
      # TODO: Add your zsh configuration steps
      logger.info "Configuring shell environment..."

      install_oh_my_zsh unless oh_my_zsh_installed?
      # TODO: Copy/symlink dotfiles (.zshrc, .zprofile, etc.)
    end

    private

    def oh_my_zsh_installed?
      File.directory?(File.expand_path("~/.oh-my-zsh"))
    end

    def install_oh_my_zsh
      logger.info "Installing Oh My Zsh..."
      cmd.run(
        'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended',
        abort_on_fail: false
      )
    end
  end
end
