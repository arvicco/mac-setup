# frozen_string_literal: true

module MacSetup
  class Homebrew < BaseModule
    # Apple-Silicon only by policy (see CLAUDE.md / past discussion). All
    # paths derive from this constant so the rest of the codebase doesn't
    # need to hard-code anything. If Intel support is ever revisited, this
    # is the one place that has to grow runtime detection.
    PREFIX = "/opt/homebrew"
    BREW_INSTALL_URL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    BREW_PATH = "#{PREFIX}/bin/brew"
    # brew's `ruby` formula is keg-only — macOS already ships /usr/bin/ruby
    # so brew refuses to link its build into /opt/homebrew/bin. The actual
    # binary lives at the keg path below, and `brew shellenv` does NOT add
    # this to PATH. Without an explicit export, `ruby` / `gem` / `bundle`
    # / `irb` all keep resolving to Apple's stock 2.6.10 (deprecated since
    # Sonoma, deprecation warning on every invocation).
    RUBY_KEG_BIN = "#{PREFIX}/opt/ruby/bin"

    # Helper for other modules: absolute path to a brew-installed binary
    # without each module having to remember the /opt/homebrew prefix or
    # the bin/ subdir. Used by Dock, DefaultBrowser, Tailscale.
    def self.bin(name)
      "#{PREFIX}/bin/#{name}"
    end

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
      # stream: true so the installer's live output (several minutes) is
      # visible instead of buffered until the end.
      cmd.run(
        %(NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL #{BREW_INSTALL_URL})"),
        abort_on_fail: true, stream: true
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

      # Keg-only ruby (see RUBY_KEG_BIN comment). Prepended to PATH so any
      # subsequent module that invokes `ruby` / `gem` / `bundle` sees the
      # brew binary, not Apple's deprecated stock 2.6.10.
      unless ENV["PATH"].include?(RUBY_KEG_BIN)
        ENV["PATH"] = "#{RUBY_KEG_BIN}:#{ENV['PATH']}"
        logger.info "Added #{RUBY_KEG_BIN} to PATH for this session (keg-only ruby)."
      end

      ruby_path_line = %(export PATH="#{RUBY_KEG_BIN}:$PATH")
      if Utils::FileEditor.ensure_line_in_file("~/.zprofile", ruby_path_line)
        logger.info "Added keg-only ruby to PATH in ~/.zprofile."
      end
    end

    # Apply the core Brewfile. The personal overlay
    # (config/personal/Brewfile) is installed by the separate
    # HomebrewPersonal module, which runs AFTER Secrets has decrypted
    # config/personal.age — Homebrew runs before Secrets (Secrets needs
    # `age` from the core Brewfile to decrypt), so the personal file
    # doesn't exist on disk during this step.
    def install_packages
      core = File.join(MacSetup::ROOT, "config", "Brewfile")
      unless File.exist?(core)
        logger.warn "No Brewfile found at #{core}"
        return
      end
      logger.info "Installing packages from Brewfile (core)..."
      # stream: true — brew bundle takes 10-20 min on a fresh Mac and
      # any sudo prompts / per-cask failures need to surface live.
      cmd.run(BREW_PATH, "bundle", "--file=#{core}", abort_on_fail: false, stream: true)
    end
  end
end
