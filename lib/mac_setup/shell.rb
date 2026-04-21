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

    # Walk the harvested tree file-by-file and mirror each into $HOME.
    # Merge semantics: siblings in the user's home that aren't in the
    # harvest are left alone (important for ~/.config/, which holds
    # per-app subtrees that other mac-setup modules also write to).
    # Backups are per-file so only the actually-replaced file is saved;
    # we don't rename entire directories out from under the user.
    def copy_dotfiles
      source_root = File.join(MacSetup::ROOT, DOTFILES_SOURCE)
      unless File.directory?(source_root)
        logger.info "No #{DOTFILES_SOURCE}/ directory; skipping dotfile copy."
        return
      end

      entries = Dir.glob("**/*", File::FNM_DOTMATCH, base: source_root)
                   .reject { |rel| [".", ".."].include?(File.basename(rel)) }
      if entries.empty?
        logger.info "No dotfiles in #{DOTFILES_SOURCE}/."
        return
      end

      entries.sort.each do |rel|
        source = File.join(source_root, rel)
        dest   = File.expand_path(File.join("~", rel))
        if File.directory?(source)
          FileUtils.mkdir_p(dest)
        else
          copy_dotfile(source, dest, rel)
        end
      end
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

    def copy_dotfile(source, dest, rel)
      # Stale symlink from older mac-setup versions that symlinked
      # dotfiles instead of copying. Preserve via backup.
      if File.symlink?(dest)
        backup = unique_backup_path(dest)
        FileUtils.mv(dest, backup)
        logger.warn "Replaced stale symlink ~/#{rel} (backed up to #{File.basename(backup)})"
      elsif File.exist?(dest)
        if File.read(dest, mode: "rb") == File.read(source, mode: "rb")
          logger.info "~/#{rel} already up to date."
          return
        end
        backup = unique_backup_path(dest)
        FileUtils.cp(dest, backup)
        logger.warn "Backed up existing ~/#{rel} to #{File.basename(backup)}"
      end

      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(source, dest)
      logger.success "Copied ~/#{rel}"
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
