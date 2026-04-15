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

      def info(msg)
        puts "#{COLORS[:blue]}[INFO]#{COLORS[:reset]} #{msg}"
      end

      def success(msg)
        puts "#{COLORS[:green]}[ OK ]#{COLORS[:reset]} #{msg}"
      end

      def warn(msg)
        puts "#{COLORS[:yellow]}[WARN]#{COLORS[:reset]} #{msg}"
      end

      def error(msg)
        $stderr.puts "#{COLORS[:red]}[ERR ]#{COLORS[:reset]} #{msg}"
      end
    end
  end
end
