# frozen_string_literal: true

require "fileutils"
require "io/console"
require "open3"
require "tempfile"

module MacSetup
  class Secrets < BaseModule
    def run
      unless File.exist?(encrypted_path)
        logger.info "No config/personal.age found. Skipping secrets decryption."
        return
      end

      if File.directory?(decrypted_path) && !Dir.empty?(decrypted_path)
        logger.info "config/personal/ already populated. Skipping decryption."
        return
      end

      unless age_installed?
        logger.warn "age not found — install it (brew install age) and re-run."
        return
      end

      decrypt
    end

    private

    def age_installed?
      cmd.success?("command -v age")
    end

    def decrypt
      passphrase = options[:passphrase] || ENV["AGE_PASSPHRASE"] || prompt_passphrase
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
          return
        end

        FileUtils.mkdir_p(decrypted_path)
        _, stderr, status = Open3.capture3("tar", "xzf", tmp.path, "-C", decrypted_path)

        unless status.success?
          FileUtils.rm_rf(decrypted_path)
          logger.error "Failed to extract decrypted archive."
          logger.error stderr unless stderr.empty?
          return
        end

        logger.success "Personal config decrypted to config/personal/."
      ensure
        File.unlink(tmp.path) if File.exist?(tmp.path)
      end
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
