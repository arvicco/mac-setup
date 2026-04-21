# frozen_string_literal: true

module MacSetup
  class Node < BaseModule
    NVM_DIR = File.expand_path("~/.nvm")
    NVM_VERSION = "0.40.1"

    def run
      install_nvm unless nvm_installed?
      ensure_nvm_in_zshrc
      install_node_lts
      add_node_to_path
    end

    private

    def nvm_installed?
      File.directory?(NVM_DIR)
    end

    def install_nvm
      logger.info "Installing nvm #{NVM_VERSION}..."
      url = "https://raw.githubusercontent.com/nvm-sh/nvm/v#{NVM_VERSION}/install.sh"
      cmd.run("curl -o- #{url} | bash", abort_on_fail: true, stream: true)
    end

    def install_node_lts
      logger.info "Installing Node.js LTS..."
      # stream: nvm install --lts downloads and compiles for several
      # minutes; live output beats a silent wait.
      cmd.run(nvm_prefix + "nvm install --lts", abort_on_fail: true, stream: true)
    end

    def add_node_to_path
      # Find the nvm-installed node binary and add it to PATH for this process
      node_bin = Dir.glob("#{NVM_DIR}/versions/node/*/bin").max
      if node_bin && !ENV["PATH"].include?(node_bin)
        ENV["PATH"] = "#{node_bin}:#{ENV['PATH']}"
        logger.info "Added #{node_bin} to PATH for this session."
      end
    end

    def ensure_nvm_in_zshrc
      block = <<~SH.chomp
        # nvm
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
      SH
      if Utils::FileEditor.ensure_block_in_file("~/.zshrc", 'export NVM_DIR="$HOME/.nvm"', block)
        logger.info "Added nvm to ~/.zshrc."
      end
    end

    def nvm_prefix
      "export NVM_DIR=\"#{NVM_DIR}\" && . \"$NVM_DIR/nvm.sh\" && "
    end
  end
end
