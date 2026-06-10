# frozen_string_literal: true

module MacSetup
  class Hostname < BaseModule
    SCUTIL_KEYS = %w[HostName ComputerName LocalHostName].freeze

    def run
      current = current_hostname
      logger.info "Current hostname: #{current}"

      name = options[:hostname] || prompt_for_hostname(current)
      if name.nil? || name.empty?
        logger.info "Keeping current hostname."
        return
      end

      SCUTIL_KEYS.each do |key|
        cmd.run("sudo", "scutil", "--set", key, name, abort_on_fail: true)
      end

      logger.success "Hostname set to '#{name}'."
    end

    private

    # Non-TTY: don't even print the prompt. A `ssh host ruby bin/setup`
    # invocation without --hostname would otherwise show a phantom prompt
    # in the log; better to silently keep the current name and trust the
    # caller to pass --hostname when they want a change. Matches the
    # Secrets module's prompt-on-tty-only pattern.
    def prompt_for_hostname(current)
      return "" unless $stdin.tty?
      print "Enter new hostname (blank to keep '#{current}'): "
      input = $stdin.gets
      input ? input.chomp.strip : ""
    end

    def current_hostname
      stdout, _stderr, _status = cmd.run("scutil", "--get", "ComputerName", abort_on_fail: false)
      stdout.strip
    end
  end
end
