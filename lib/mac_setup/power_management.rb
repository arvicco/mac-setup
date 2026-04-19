# frozen_string_literal: true

module MacSetup
  class PowerManagement < BaseModule
    def run
      disable_low_power_mode
      prevent_sleep_on_ac
      prevent_sleep_on_battery
    end

    private

    def disable_low_power_mode
      logger.info "Disabling low power mode (all power sources)..."
      cmd.run("sudo", "pmset", "-a", "lowpowermode", "0")
    end

    def prevent_sleep_on_ac
      logger.info "Preventing auto-sleep on AC power when display is off..."
      cmd.run("sudo", "pmset", "-c", "sleep", "0")
    end

    # Battery = power-outage scenario: we want the machine to keep running
    # (serving, syncing) until the battery dies, not sleep after a few minutes.
    def prevent_sleep_on_battery
      logger.info "Preventing auto-sleep on battery power (ride-through on outage)..."
      cmd.run("sudo", "pmset", "-b", "sleep", "0")
      cmd.run("sudo", "pmset", "-b", "disksleep", "0")
    end
  end
end
