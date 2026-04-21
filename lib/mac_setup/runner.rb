# frozen_string_literal: true

require "fileutils"
require "optparse"

module MacSetup
  class Runner
    MODULES = [
      Hostname,
      Homebrew,
      Secrets,
      Node,
      ClaudeCode,
      Cask,
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

      acquire_sudo(logger)
      modules_to_run = select_modules(logger)

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

    private

    def acquire_sudo(logger)
      logger.info "Some steps require admin privileges."
      system("sudo -v")
      # Keep sudo alive in the background for the duration of the script
      @sudo_keepalive = Thread.new do
        loop do
          system("sudo -n true")
          sleep 50
        end
      end
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
