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
      #   redact:         array of regexes. Any arg matching one of them
      #                   gets the matched portion replaced with `<redacted>`
      #                   in the echoed `$ cmd` line. The real value still
      #                   reaches exec. Centralizes the "don't leak a token
      #                   into the log" pattern so future callers can opt
      #                   in without rolling their own quiet+manual-log.
      def run(*args, abort_on_fail: false, quiet: false, stream: false, redact: [])
        raise ArgumentError, "run requires at least one argument" if args.empty?

        logger.info "$ #{display(args, redact)}" unless quiet

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
            logger.error "Command failed (exit #{status.exitstatus}): #{display(args, redact)}"
            logger.error scrub(stderr, redact) unless stderr.empty?
            exit 1
          elsif !quiet
            logger.error "Command failed (exit #{status.exitstatus}): #{display(args, redact)}"
            logger.error scrub(stderr, redact) unless stderr.empty?
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

      def display(args, redact = [])
        rendered = args.map { |a| redact_arg(a.to_s, redact) }
        rendered.length == 1 ? rendered.first : Shellwords.join(rendered)
      end

      # Whole-arg replacement is the safe default: a regex like
      # /tskey-[a-z0-9]+/ that matches the secret value alone would
      # otherwise echo the secret followed by "<redacted>" (m[0] is the
      # match). Replacing the entire arg means callers can't shoot
      # themselves regardless of how their regex anchors.
      def redact_arg(arg, patterns)
        return arg if patterns.empty?
        return "<redacted>" if patterns.any? { |re| arg.match?(re) }
        arg
      end

      # Scrub captured stderr/stdout for any matched substring before
      # emitting it to the log. Without this, `tailscale up` could echo
      # the auth-key back in its validation error, defeating the redact:
      # option's intent on the failure path. Per-line scan so the rest
      # of the message stays useful for triage.
      def scrub(text, patterns)
        return text if patterns.empty?
        patterns.reduce(text) { |t, re| t.gsub(re, "<redacted>") }
      end
    end
  end
end
