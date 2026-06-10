# frozen_string_literal: true

module MacSetup
  # Decides which modules a run will execute, based on CLI options + argv:
  #
  #   --all                 → every module in MODULES, in order
  #   one or more names     → just those modules, in MODULES order
  #   (none, TTY)           → interactive Y/n prompt per module
  #   (none, non-TTY)       → abort with a clear error
  #
  # Extracted from Runner so the selection logic can be tested without
  # spinning up the whole run lifecycle, and so future selection knobs
  # (`--from <name>`, `--skip <name>`, etc.) have a natural home.
  class ModuleSelector
    def initialize(modules:, options:, argv:)
      @modules = modules
      @options = options
      @argv    = argv
    end

    def select(logger)
      return @modules if @options[:all]

      unless @argv.empty?
        names = @argv.map { |n| normalize_name(n) }
        return @modules.select { |m| names.include?(normalize_name(m.module_name)) }
      end

      unless $stdin.tty?
        logger.error "No TTY for interactive prompts and no module selection given."
        logger.error "Pass --all to run every module, or list specific module names (see --list)."
        exit 1
      end

      prompt_for_each
    end

    private

    def normalize_name(name)
      name.downcase.gsub(/\s+/, "")
    end

    def prompt_for_each
      selected = []
      @modules.each do |mod_class|
        print "Run #{mod_class.module_name}? [Y/n] "
        input = $stdin.gets
        answer = input ? input.chomp.strip.downcase : ""
        selected << mod_class unless answer == "n"
      end
      selected
    end
  end
end
