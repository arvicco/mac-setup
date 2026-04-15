# frozen_string_literal: true

module MacSetup
  class Homebrew < BaseModule
    BREW_INSTALL_URL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    BREW_PATH = "/opt/homebrew/bin/brew"

    def run
      install_homebrew unless homebrew_installed?
      configure_path
      install_packages
    end

    private

    def homebrew_installed?
      File.exist?(BREW_PATH)
    end

    def install_homebrew
      logger.info "Installing Homebrew..."
      cmd.run('/bin/bash -c "$(curl -fsSL ' + BREW_INSTALL_URL + ')"', abort_on_fail: true)
    end

    def configure_path
      # Add brew to PATH for the current process
      brew_bin = File.dirname(BREW_PATH)
      unless ENV["PATH"].include?(brew_bin)
        ENV["PATH"] = "#{brew_bin}:#{ENV['PATH']}"
        logger.info "Added #{brew_bin} to PATH for this session."
      end

      # Ensure brew shellenv is in .zprofile for future shells
      zprofile = File.expand_path("~/.zprofile")
      shellenv_line = 'eval "$(/opt/homebrew/bin/brew shellenv)"'
      unless File.exist?(zprofile) && File.read(zprofile).include?(shellenv_line)
        File.open(zprofile, "a") { |f| f.puts("", shellenv_line) }
        logger.info "Added brew shellenv to ~/.zprofile."
      end
    end

    def install_packages
      brewfile = File.join(MacSetup::ROOT, "config", "Brewfile")
      if File.exist?(brewfile)
        logger.info "Installing packages from Brewfile..."
        cmd.run("#{BREW_PATH} bundle --file=#{brewfile}", abort_on_fail: false)
      else
        logger.warn "No Brewfile found at #{brewfile}"
      end
    end
  end
end
