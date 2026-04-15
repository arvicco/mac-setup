# frozen_string_literal: true

module MacSetup
  class Node < BaseModule
    def run
      # TODO: Choose your Node version manager (nvm, nodenv, fnm)
      install_nvm unless nvm_installed?
      install_node_lts
    end

    private

    def nvm_installed?
      File.directory?(File.expand_path("~/.nvm"))
    end

    def install_nvm
      logger.info "Installing nvm..."
      cmd.run(
        "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash",
        abort_on_fail: false
      )
    end

    def install_node_lts
      logger.info "Installing Node.js LTS..."
      # nvm needs to be sourced in the same shell
      cmd.run(
        'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm install --lts',
        abort_on_fail: false
      )
    end
  end
end
