# frozen_string_literal: true

module MacSetup
  module Utils
    class Logger
      COLORS = {
        red:    "\e[31m",
        green:  "\e[32m",
        yellow: "\e[33m",
        blue:   "\e[34m",
        reset:  "\e[0m"
      }.freeze

      # log_file: optional IO (or nil). When provided, every log line is
      # also appended to it without ANSI codes so the file reads cleanly.
      # Streamed command output (cmd.run(..., stream: true)) bypasses
      # this path — for those, terminal scrollback is the source of truth.
      attr_reader :error_count

      def initialize(log_file: nil)
        @log_file = log_file
        @error_count = 0
      end

      def info(msg)
        emit("INFO", COLORS[:blue], msg, $stdout)
      end

      def success(msg)
        emit(" OK ", COLORS[:green], msg, $stdout)
      end

      def warn(msg)
        emit("WARN", COLORS[:yellow], msg, $stdout)
      end

      def error(msg)
        @error_count += 1
        emit("ERR ", COLORS[:red], msg, $stderr)
      end

      private

      def emit(tag, color, msg, io)
        io.puts "#{color}[#{tag}]#{COLORS[:reset]} #{msg}"
        return unless @log_file
        @log_file.puts "[#{tag}] #{msg}"
        @log_file.flush
      end
    end
  end
end
