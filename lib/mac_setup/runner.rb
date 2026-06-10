# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"

module MacSetup
  class Runner
    MODULES = [
      Hostname,
      Homebrew,
      Secrets,
      HomebrewPersonal,
      Node,
      Dotfiles,
      ClaudeCode,
      DefaultBrowser,
      MacosDefaults,
      Dock,
      AutoLogin,
      PowerManagement,
      Security,
      Karabiner,
      KeyboardLayouts,
      KeyboardShortcuts,
      GitConfig,
      Shell,
      Iterm2,
      Ssh,
      GithubAuth,
      Rclone,
      Tailscale
    ].freeze

    def initialize(argv = [])
      @argv = argv
      @options = {}
      parse_options
    end

    def run
      if @options[:help]
        puts @parser
        return
      end

      if @options[:list]
        list_modules
        return
      end

      log_file = open_log_file
      logger = Utils::Logger.new(log_file: log_file)
      cmd = Utils::CommandRunner.new(logger: logger)

      logger.info "Mac Setup v#{MacSetup::VERSION}"
      logger.info "Log: #{log_file.path}" if log_file
      logger.info "=" * 40

      modules_to_run = select_modules(logger)

      if modules_to_run.empty?
        logger.warn "No modules to run."
        return
      end

      acquire_sudo(logger)

      modules_to_run.each do |mod_class|
        mod = mod_class.new(logger: logger, cmd: cmd, options: @options)
        logger.info ""
        logger.info "Running: #{mod.name}"
        logger.info "-" * 40
        errors_before = logger.error_count
        mod.run
        if logger.error_count > errors_before
          logger.error "#{mod.name} completed with errors — see above."
        else
          logger.success "#{mod.name} complete."
        end
      end

      cleanup_secrets(logger)

      logger.info ""
      if logger.error_count.zero?
        logger.success "All done! Open a new terminal for all tools to be available."
      else
        logger.error "Finished with #{logger.error_count} error(s). Open a new terminal for all tools to be available."
      end
    ensure
      log_file&.close
    end

    # Opens a per-run log file at log/setup-<timestamp>.log in the repo.
    # Gitignored. Captures everything Logger emits (info/success/warn/error).
    # Does NOT capture output from streamed commands (cmd.run(..., stream: true))
    # — those inherit the parent's stdout/stderr directly; use terminal
    # scrollback if you need the brew/nvm body text.
    def open_log_file
      log_dir = File.join(MacSetup::ROOT, "log")
      FileUtils.mkdir_p(log_dir)
      prune_old_logs(log_dir)
      path = File.join(log_dir, "setup-#{Time.now.strftime("%Y%m%d-%H%M%S")}.log")
      file = File.open(path, "a")
      file.sync = true
      file
    rescue StandardError => e
      # If we can't open the log file, carry on without it — better to
      # run setup and lose the trace than refuse to run at all.
      warn "Could not open log file (#{e.message}); continuing without file logging."
      nil
    end

    # Drop setup-*.log files older than `days` days. Keeps the log/
    # directory from accumulating one-per-run forever on long-lived
    # home-server installs. Only matches our own naming pattern so
    # stray files in log/ (e.g., a user's hand-saved snapshot) survive.
    def prune_old_logs(log_dir, days: 30)
      return unless File.directory?(log_dir)
      cutoff = Time.now - (days * 86400)
      Dir.glob(File.join(log_dir, "setup-*.log")).each do |path|
        File.unlink(path) if File.mtime(path) < cutoff
      end
    rescue StandardError
      # Best-effort: a permissions hiccup must not block the setup run.
    end

    private

    def acquire_sudo(logger)
      @sudo_session = SudoSession.new(logger: logger)
      @sudo_session.acquire
    end

    # Opt-in via --cleanup-secrets. Removes the decrypted config/personal/
    # tree after a successful run so plaintext secrets (gh_token, tailscale
    # OAuth client_secret, autologin password) don't sit on disk after a
    # one-shot bootstrap. The encrypted config/personal.age stays — re-runs
    # that need personal config will re-decrypt from it (Secrets module
    # detects the missing dir and re-extracts).
    #
    # Skipped if any module errored: the user almost certainly needs to
    # inspect or re-run, and forcing them to re-type the passphrase is
    # punishment for an already-bad run.
    def cleanup_secrets(logger)
      return unless @options[:cleanup_secrets]

      path = decrypted_personal_path
      bak_pattern = File.join(File.dirname(path), "#{File.basename(path)}.bak-*")
      bak_dirs = Dir.glob(bak_pattern).select { |p| File.directory?(p) }

      return if !File.directory?(path) && bak_dirs.empty?

      if logger.error_count > 0
        logger.warn "--cleanup-secrets requested but #{logger.error_count} module error(s) — keeping config/personal/ and any backups for re-run."
        return
      end

      if File.directory?(path)
        FileUtils.rm_rf(path)
        logger.success "Removed config/personal/ (--cleanup-secrets). Re-run will re-decrypt from personal.age."
      end
      bak_dirs.each do |bak|
        FileUtils.rm_rf(bak)
        logger.success "Removed #{File.basename(bak)} (--cleanup-secrets)."
      end
    end

    def decrypted_personal_path
      File.join(MacSetup::ROOT, "config", "personal")
    end

    def parse_options
      @parser = OptionParser.new do |opts|
        opts.banner = "Usage: setup [options] [module ...]"

        opts.on("-l", "--list", "List available modules") do
          @options[:list] = true
        end

        opts.on("-a", "--all", "Run all modules without prompting") do
          @options[:all] = true
        end

        opts.on("--hostname NAME", "Set machine hostname (skips Hostname prompt)") do |v|
          @options[:hostname] = v
        end

        opts.on("--git-name NAME", "Set git user.name (skips GitConfig prompt)") do |v|
          @options[:git_name] = v
        end

        opts.on("--git-email EMAIL", "Set git user.email (skips GitConfig prompt)") do |v|
          @options[:git_email] = v
        end

        opts.on("--passphrase PASS", "Passphrase for decrypting config/personal.age") do |v|
          @options[:passphrase] = v
        end

        opts.on("--autologin", "Enable boot-time auto-login (reads config/personal/autologin.yml if present)") do
          @options[:autologin] = true
        end

        opts.on("--github-ssh", "Generate a dedicated SSH key for github.com and upload to GitHub (default: HTTPS via gh credential helper)") do
          @options[:github_ssh] = true
        end

        opts.on("--cleanup-secrets", "After successful run, remove the decrypted config/personal/ directory so plaintext secrets (gh_token, tailscale OAuth secret, autologin password) don't sit on disk. Re-runs re-decrypt from personal.age.") do
          @options[:cleanup_secrets] = true
        end

        opts.on("-h", "--help", "Show this help") do
          @options[:help] = true
        end
      end
      @parser.parse!(@argv)
    end

    def list_modules
      puts "Available modules:"
      MODULES.each_with_index do |mod, i|
        puts "  #{i + 1}. #{mod.module_name}"
      end
    end

    def normalize_name(name)
      name.downcase.gsub(/\s+/, "")
    end

    def select_modules(logger)
      return MODULES if @options[:all]

      unless @argv.empty?
        names = @argv.map { |n| normalize_name(n) }
        return MODULES.select { |m| names.include?(normalize_name(m.module_name)) }
      end

      # Interactive prompt loop only makes sense on a TTY. Without this
      # guard, a non-interactive `ssh host ruby bin/setup` (no --all, no
      # module names) hit EOF on every prompt → defaulted "Y" on each →
      # ran the entire suite unattended. Conservative behavior: refuse
      # and tell the user the right invocation.
      unless $stdin.tty?
        logger.error "No TTY for interactive prompts and no module selection given."
        logger.error "Pass --all to run every module, or list specific module names (see --list)."
        exit 1
      end

      selected = []
      MODULES.each do |mod_class|
        print "Run #{mod_class.module_name}? [Y/n] "
        input = $stdin.gets
        answer = input ? input.chomp.strip.downcase : ""
        selected << mod_class unless answer == "n"
      end
      selected
    end
  end
end
