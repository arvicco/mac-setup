# frozen_string_literal: true

require "optparse"

module MacSetup
  class Runner
    MODULES = [
      Hostname,
      Homebrew,
      Node,
      ClaudeCode,
      Cask,
      MacosDefaults,
      GitConfig,
      Shell,
      Ssh
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

      logger = Utils::Logger.new
      cmd = Utils::CommandRunner.new(logger: logger)

      logger.info "Mac Setup v#{MacSetup::VERSION}"
      logger.info "=" * 40

      acquire_sudo(logger)
      modules_to_run = select_modules(logger)

      modules_to_run.each do |mod_class|
        mod = mod_class.new(logger: logger, cmd: cmd)
        logger.info ""
        logger.info "Running: #{mod.name}"
        logger.info "-" * 40
        mod.run
        logger.success "#{mod.name} complete."
      end

      logger.info ""
      logger.success "All done!"
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

    def select_modules(logger)
      return MODULES if @options[:all]

      unless @argv.empty?
        names = @argv.map(&:downcase)
        return MODULES.select { |m| names.include?(m.module_name.downcase) }
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
