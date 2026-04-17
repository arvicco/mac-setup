# frozen_string_literal: true

require "fileutils"
require "io/console"
require "open3"
require "shellwords"
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
      cmd.success?("command", "-v", "age")
    end

    def decrypt
      passphrase = options[:passphrase] || prompt_passphrase
      if passphrase.nil? || passphrase.empty?
        logger.warn "No passphrase provided. Skipping secrets decryption."
        return
      end

      logger.info "Decrypting config/personal.age..."

      tmp = Tempfile.new(["personal", ".tar.gz"])
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
        tmp.close
        tmp.unlink
      end
    end

    # age reads the passphrase from /dev/tty, which requires a pty.
    # We use expect(1) (ships with macOS) to provide one so this works
    # both interactively and over SSH.
    def age_decrypt(passphrase, output_path)
      escaped_out = Shellwords.escape(output_path)
      escaped_in  = Shellwords.escape(encrypted_path)

      # Tcl strings use $ for variable interpolation, so we pass the
      # passphrase via env var to avoid escaping hell.
      script = 'set passphrase $env(AGE_PASSPHRASE); ' \
        "spawn age -d -o #{escaped_out} #{escaped_in}; " \
        'expect "Enter passphrase:"; ' \
        'send "$passphrase\r"; ' \
        'expect eof; ' \
        'lassign [wait] _ _ _ code; ' \
        'exit $code'

      _, stderr, status = Open3.capture3(
        { "AGE_PASSPHRASE" => passphrase },
        "expect", "-c", script
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
