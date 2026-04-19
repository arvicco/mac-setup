# frozen_string_literal: true

require "fileutils"

module MacSetup
  class Shell < BaseModule
    DOTFILES_SOURCE = File.join("config", "personal", "dotfiles")

    def run
      logger.info "Configuring shell environment..."
      install_oh_my_zsh unless oh_my_zsh_installed?
      copy_dotfiles
    end

    # Copy (not symlink) so that removing the mac-setup checkout after
    # initial provisioning doesn't break every dotfile. Backups preserve
    # anything pre-existing instead of clobbering it.
    def copy_dotfiles
      source_dir = File.join(MacSetup::ROOT, DOTFILES_SOURCE)
      unless File.directory?(source_dir)
        logger.info "No #{DOTFILES_SOURCE}/ directory; skipping dotfile copy."
        return
      end

      entries = Dir.children(source_dir).sort.select do |name|
        File.file?(File.join(source_dir, name))
      end
      if entries.empty?
        logger.info "No dotfiles in #{DOTFILES_SOURCE}/."
        return
      end

      entries.each { |name| copy_dotfile(source_dir, name) }
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

    def copy_dotfile(source_dir, name)
      source = File.join(source_dir, name)
      dest   = File.expand_path("~/#{name}")

      # Idempotent: same bytes → no-op. Also cleans up a stale symlink
      # left over from older mac-setup versions that used symlinks.
      if File.symlink?(dest)
        backup = unique_backup_path(dest)
        FileUtils.mv(dest, backup)
        logger.warn "Replaced stale symlink ~/#{name} (backed up to #{File.basename(backup)})"
      elsif File.exist?(dest)
        if File.read(dest, mode: "rb") == File.read(source, mode: "rb")
          logger.info "~/#{name} already up to date."
          return
        end
        backup = unique_backup_path(dest)
        FileUtils.cp(dest, backup)
        logger.warn "Backed up existing ~/#{name} to #{File.basename(backup)}"
      end

      FileUtils.cp(source, dest)
      logger.success "Copied ~/#{name}"
    end

    # `.bak-YYYYMMDD-HHMMSS` collides on re-runs within the same second.
    # Append a counter until we find a free slot so we never clobber an
    # older backup — the whole point of a backup is recoverability.
    def unique_backup_path(dest)
      base = "#{dest}.bak-#{Time.now.strftime("%Y%m%d-%H%M%S")}"
      candidate = base
      i = 1
      while File.exist?(candidate) || File.symlink?(candidate)
        candidate = "#{base}.#{i}"
        i += 1
      end
      candidate
    end
  end
end
