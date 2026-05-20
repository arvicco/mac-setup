# frozen_string_literal: true

module MacSetup
  # Applies the personal Brewfile overlay (config/personal/Brewfile)
  # AFTER Secrets has decrypted config/personal.age.
  #
  # Split from the Homebrew module because that one runs BEFORE Secrets
  # — it has to, since Secrets needs `age` from the core Brewfile to
  # decrypt the archive. Trying to install personal-overlay packages in
  # the same Homebrew module would silently no-op (the file doesn't exist
  # on disk yet), which is exactly the bug that hid tailscale-app from
  # post-bootstrap installs for months.
  class HomebrewPersonal < BaseModule
    PERSONAL_BREWFILE = File.join("config", "personal", "Brewfile")

    def run
      path = personal_brewfile_path
      unless File.exist?(path)
        logger.info "No #{PERSONAL_BREWFILE} (Secrets may have skipped). Skipping personal Brewfile."
        return
      end

      logger.info "Installing packages from config/personal/Brewfile (overlay)..."
      cmd.run(
        Homebrew::BREW_PATH, "bundle", "--file=#{path}",
        abort_on_fail: false, stream: true,
      )
    end

    private

    def personal_brewfile_path
      File.join(MacSetup::ROOT, PERSONAL_BREWFILE)
    end
  end
end
