# frozen_string_literal: true

module MacSetup
  class Hostname < BaseModule
    SCUTIL_KEYS = %w[HostName ComputerName LocalHostName].freeze

    def run
      current = current_hostname
      logger.info "Current hostname: #{current}"

      print "Enter new hostname (blank to keep '#{current}'): "
      name = $stdin.gets.chomp.strip
      if name.empty?
        logger.info "Keeping current hostname."
        return
      end

      SCUTIL_KEYS.each do |key|
        cmd.run("sudo scutil --set #{key} #{name}", abort_on_fail: true)
      end

      logger.success "Hostname set to '#{name}'."
    end

    private

    def current_hostname
      stdout, = cmd.run("scutil --get ComputerName", abort_on_fail: false)
      stdout.strip
    end
  end
end
