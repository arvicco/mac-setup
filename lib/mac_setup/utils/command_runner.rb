# frozen_string_literal: true

require "open3"

module MacSetup
  module Utils
    class CommandRunner
      attr_reader :logger

      def initialize(logger:)
        @logger = logger
      end

      # Run a command, return [stdout, stderr, status]
      # quiet: true suppresses error logging (for commands where failure is expected)
      def run(command, abort_on_fail: false, quiet: false)
        logger.info "$ #{command}" unless quiet
        stdout, stderr, status = Open3.capture3(command)

        unless status.success?
          if abort_on_fail
            logger.error "Command failed (exit #{status.exitstatus}): #{command}"
            logger.error stderr unless stderr.empty?
            exit 1
          elsif !quiet
            logger.error "Command failed (exit #{status.exitstatus}): #{command}"
            logger.error stderr unless stderr.empty?
          end
        end

        [stdout, stderr, status]
      end

      # Run a command, return true if exit 0
      def success?(command)
        _, _, status = Open3.capture3(command)
        status.success?
      end
    end
  end
end
