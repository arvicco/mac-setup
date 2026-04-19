# frozen_string_literal: true

module MacSetup
  class Security < BaseModule
    FIREWALL_CMD = "/usr/libexec/ApplicationFirewall/socketfilterfw"

    def run
      enable_firewall
    end

    private

    def enable_firewall
      logger.info "Enabling firewall..."
      cmd.run("sudo", FIREWALL_CMD, "--setglobalstate", "on")
    end
  end
end
