# frozen_string_literal: true

module MacSetup
  class BaseModule
    attr_reader :logger, :cmd

    def initialize(logger:, cmd:)
      @logger = logger
      @cmd = cmd
    end

    def name
      self.class.module_name
    end

    def self.module_name
      self.name.split("::").last
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1 \2')
        .gsub(/([a-z\d])([A-Z])/, '\1 \2')
    end

    def run
      raise NotImplementedError, "#{self.class}#run must be implemented"
    end
  end
end
