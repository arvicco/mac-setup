# frozen_string_literal: true

module MacSetup
  class Homebrew < BaseModule
    BREW_INSTALL_URL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

    def run
      install_homebrew unless homebrew_installed?
      install_packages
    end

    private

    def homebrew_installed?
      cmd.success?("command -v brew")
    end

    def install_homebrew
      logger.info "Installing Homebrew..."
      cmd.run(%(bash -c "$(curl -fsSL #{BREW_INSTALL_URL})"), abort_on_fail: true)
    end

    def install_packages
      brewfile = File.join(MacSetup::ROOT, "config", "Brewfile")
      if File.exist?(brewfile)
        logger.info "Installing packages from Brewfile..."
        cmd.run("brew bundle --file=#{brewfile}", abort_on_fail: false)
      else
        logger.warn "No Brewfile found at #{brewfile}"
      end
    end
  end
end
