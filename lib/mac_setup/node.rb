# frozen_string_literal: true

module MacSetup
  class Node < BaseModule
    NVM_DIR = File.expand_path("~/.nvm")

    def run
      install_nvm unless nvm_installed?
      install_node_lts
      add_node_to_path
    end

    private

    def nvm_installed?
      File.directory?(NVM_DIR)
    end

    def install_nvm
      logger.info "Installing nvm..."
      cmd.run(
        "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash",
        abort_on_fail: true
      )
    end

    def install_node_lts
      logger.info "Installing Node.js LTS..."
      cmd.run(nvm_prefix + "nvm install --lts", abort_on_fail: true)
    end

    def add_node_to_path
      # Find the nvm-installed node binary and add it to PATH for this process
      node_bin = Dir.glob("#{NVM_DIR}/versions/node/*/bin").max
      if node_bin && !ENV["PATH"].include?(node_bin)
        ENV["PATH"] = "#{node_bin}:#{ENV['PATH']}"
        logger.info "Added #{node_bin} to PATH for this session."
      end
    end

    def nvm_prefix
      "export NVM_DIR=\"#{NVM_DIR}\" && . \"$NVM_DIR/nvm.sh\" && "
    end
  end
end
