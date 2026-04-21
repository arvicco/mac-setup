# frozen_string_literal: true

require "digest"
require "fileutils"
require "io/console"
require "open3"
require "tempfile"

module MacSetup
  class Secrets < BaseModule
    STAMP_FILE = ".age-source-sha256"

    def run
      unless File.exist?(encrypted_path)
        logger.info "No config/personal.age found. Skipping secrets decryption."
        return
      end

      if up_to_date?
        logger.info "config/personal/ already decrypted from current config/personal.age; skipping."
        return
      end

      unless age_installed?
        logger.warn "age not found — install it (brew install age) and re-run."
        return
      end

      @backup_path = backup_existing_personal
      decrypt
    end

    private

    # True when config/personal/ was decrypted from the exact archive
    # that sits at config/personal.age right now. Checked via a SHA256
    # stamp we drop into the decrypted dir — keeps re-runs fast and
    # auto-re-decrypts when the user pulls a fresher personal.age.
    def up_to_date?
      return false unless File.directory?(decrypted_path)
      return false if Dir.empty?(decrypted_path)

      stamp_path = File.join(decrypted_path, STAMP_FILE)
      return false unless File.exist?(stamp_path)

      File.read(stamp_path).strip == age_source_hash
    end

    def age_source_hash
      Digest::SHA256.file(encrypted_path).hexdigest
    end

    # Before re-decrypt: move the stale personal/ tree aside so nothing
    # the user may have edited gets silently clobbered (CLAUDE.md's
    # atomic-actions rule — stage before destroying). The backup keeps
    # the stale stamp too; we only need the *current* decrypt to succeed.
    def backup_existing_personal
      return nil unless File.directory?(decrypted_path) && !Dir.empty?(decrypted_path)
      backup = "#{decrypted_path}.bak-#{Time.now.strftime("%Y%m%d-%H%M%S")}"
      FileUtils.mv(decrypted_path, backup)
      logger.warn "Stale #{File.basename(decrypted_path)}/ moved to #{File.basename(backup)} before re-decrypt."
      backup
    end

    def age_installed?
      cmd.success?("command -v age")
    end

    def decrypt
      passphrase = resolve_passphrase
      if passphrase.nil? || passphrase.empty?
        logger.warn "No passphrase provided. Skipping secrets decryption."
        return
      end

      logger.info "Decrypting config/personal.age..."

      tmp = Tempfile.new(["personal", ".tar.gz"])
      tmp.close
      File.unlink(tmp.path)
      begin
        success, stderr = age_decrypt(passphrase, tmp.path)

        unless success
          logger.error "Decryption failed. Wrong passphrase?"
          logger.error stderr unless stderr.empty?
          note_backup_on_failure
          return
        end

        FileUtils.mkdir_p(decrypted_path)
        _, stderr, status = Open3.capture3("tar", "xzf", tmp.path, "-C", decrypted_path)

        unless status.success?
          FileUtils.rm_rf(decrypted_path)
          logger.error "Failed to extract decrypted archive."
          logger.error stderr unless stderr.empty?
          note_backup_on_failure
          return
        end

        write_stamp
        logger.success "Personal config decrypted to config/personal/."
      ensure
        File.unlink(tmp.path) if File.exist?(tmp.path)
      end
    end

    # Drop a SHA256 of the source archive inside the decrypted dir so
    # up_to_date? can short-circuit on future runs. Not a secret —
    # just the hash of the ciphertext.
    def write_stamp
      File.write(File.join(decrypted_path, STAMP_FILE), age_source_hash)
    end

    # If decrypt/extract fails AFTER we've already moved the stale
    # personal/ aside, the target dir is gone and the user has no
    # cue where their previous state lives. Point at the backup so
    # recovery is a one-liner (`mv config/personal.bak-<ts> config/personal`).
    def note_backup_on_failure
      return unless @backup_path
      logger.error "Your previous config/personal/ is preserved at #{File.basename(@backup_path)}."
      logger.error "To restore: mv config/#{File.basename(@backup_path)} config/personal"
    end

    # age reads the passphrase from /dev/tty, which fails when we were
    # invoked over SSH without -t (no controlling TTY). script(1) allocates
    # its own pty and runs age inside it; the passphrase fed over stdin is
    # forwarded through that pty, so age's /dev/tty read succeeds.
    def age_decrypt(passphrase, output_path)
      _, stderr, status = Open3.capture3(
        "script", "-q", "/dev/null",
        "age", "-d", "-o", output_path, encrypted_path,
        stdin_data: "#{passphrase}\n"
      )
      [status.success?, stderr]
    end

    # Priority: --passphrase CLI flag (argv, visible in ps briefly) >
    # AGE_PASSPHRASE env var (not visible in ps) > interactive TTY prompt
    # (GUI-mode only; returns nil in non-interactive sessions).
    # Documented in docs/personal-config.md:141; keep in sync.
    def resolve_passphrase
      options[:passphrase] || ENV["AGE_PASSPHRASE"] || prompt_passphrase
    end

    def prompt_passphrase
      return nil unless $stdin.tty?

      print "Enter passphrase for config/personal.age: "
      passphrase = $stdin.noecho { $stdin.gets }
      puts
      passphrase&.chomp
    end

    def encrypted_path
      @encrypted_path ||= File.join(MacSetup::ROOT, "config", "personal.age")
    end

    def decrypted_path
      @decrypted_path ||= File.join(MacSetup::ROOT, "config", "personal")
    end
  end
end
