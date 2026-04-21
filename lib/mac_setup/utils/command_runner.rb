# frozen_string_literal: true

require "open3"
require "shellwords"

module MacSetup
  module Utils
    class CommandRunner
      attr_reader :logger

      def initialize(logger:)
        @logger = logger
      end

      # Run a command, return [stdout, stderr, status]
      #
      # Two calling forms:
      #   run("brew bundle --file=foo")                 # shell form — interprets pipes, quotes, $(...)
      #   run("git", "config", "--global", key, value)  # exec form  — no shell, args passed directly
      #
      # Use the exec form whenever args come from user input, YAML, or anywhere
      # untrusted — it makes shell injection impossible.
      #
      # Options (trailing hash):
      #   abort_on_fail:  exit the process on non-zero (default false)
      #   quiet:          suppress "$ cmd" echo and error log (default false)
      #   stream:         inherit parent's stdout/stderr so output is live;
      #                   returns ["", "", status] since nothing is captured.
      #                   Use for long-running commands (brew bundle, nvm
      #                   install, oh-my-zsh install) where waiting silently
      #                   is worse than losing the post-hoc recap on failure.
      def run(*args, abort_on_fail: false, quiet: false, stream: false)
        raise ArgumentError, "run requires at least one argument" if args.empty?

        logger.info "$ #{display(args)}" unless quiet

        if stream
          system(*args)
          status = $? # Process::Status of the child; always set after system()
          stdout = ""
          stderr = ""
        else
          stdout, stderr, status = Open3.capture3(*args)
        end

        unless status.success?
          if abort_on_fail
            logger.error "Command failed (exit #{status.exitstatus}): #{display(args)}"
            logger.error stderr unless stderr.empty?
            exit 1
          elsif !quiet
            logger.error "Command failed (exit #{status.exitstatus}): #{display(args)}"
            logger.error stderr unless stderr.empty?
          end
        end

        [stdout, stderr, status]
      end

      # Run a command, return true if exit 0. Accepts the same calling forms as #run.
      def success?(*args)
        _, _, status = Open3.capture3(*args)
        status.success?
      end

      private

      def display(args)
        args.length == 1 ? args.first : Shellwords.join(args)
      end
    end
  end
end
