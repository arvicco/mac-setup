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
      # NONINTERACTIVE=1 skips the "Press RETURN to continue" prompt so this
      # works in headless VM runs (see tasks/vm.rake).
      cmd.run(
        %(NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL #{BREW_INSTALL_URL})"),
        abort_on_fail: true
      )
    end

    def configure_path
      # Add brew to PATH for the current process
      brew_bin = File.dirname(BREW_PATH)
      unless ENV["PATH"].include?(brew_bin)
        ENV["PATH"] = "#{brew_bin}:#{ENV['PATH']}"
        logger.info "Added #{brew_bin} to PATH for this session."
      end

      # Ensure brew shellenv is in .zprofile for future shells
      shellenv_line = 'eval "$(/opt/homebrew/bin/brew shellenv)"'
      if Utils::FileEditor.ensure_line_in_file("~/.zprofile", shellenv_line)
        logger.info "Added brew shellenv to ~/.zprofile."
      end
    end

    # Apply core Brewfile first, then the optional personal overlay
    # (config/personal/Brewfile — gitignored, travels inside personal.age).
    # `brew bundle` is idempotent per package so running twice across both
    # files is safe; the overlay just adds your per-user extras on top of
    # the mandatory core packages.
    def install_packages
      core     = File.join(MacSetup::ROOT, "config", "Brewfile")
      personal = File.join(MacSetup::ROOT, "config", "personal", "Brewfile")

      applied = 0
      if File.exist?(core)
        logger.info "Installing packages from Brewfile (core)..."
        cmd.run(BREW_PATH, "bundle", "--file=#{core}", abort_on_fail: false)
        applied += 1
      else
        logger.warn "No Brewfile found at #{core}"
      end

      if File.exist?(personal)
        logger.info "Installing packages from config/personal/Brewfile (overlay)..."
        cmd.run(BREW_PATH, "bundle", "--file=#{personal}", abort_on_fail: false)
        applied += 1
      end

      logger.warn "No Brewfile applied." if applied.zero?
    end
  end
end
