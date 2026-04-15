# frozen_string_literal: true

module MacSetup
  class Cask < BaseModule
    # Cask apps are declared in config/Brewfile under the "cask" entries.
    # This module exists as a placeholder for any cask-specific logic
    # (e.g., post-install configuration, verifying app launches).

    def run
      # TODO: Add cask-specific post-install steps here
      logger.info "Cask apps are installed via Brewfile (see Homebrew module)."
      logger.info "Add post-install configuration here as needed."
    end
  end
end
