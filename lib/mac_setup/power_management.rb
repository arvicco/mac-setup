# frozen_string_literal: true

module MacSetup
  class PowerManagement < BaseModule
    def run
      disable_low_power_mode
      prevent_sleep_on_ac
      prevent_sleep_on_battery
      disable_all_sleep
      auto_restart_after_outage
      wake_on_network
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

    # `pmset -a sleep 0` only zeros the inactivity timer. The machine still
    # sleeps on lid close (clamshell), on emergency low battery (~3%), and
    # on any IOPMAssertion-based sleep request from an app. For a home
    # server we want NONE of those — this is the kernel-level master
    # switch that disables all of them at once.
    def disable_all_sleep
      logger.info "Disabling all sleep paths (lid close, low battery, app requests)..."
      cmd.run("sudo", "pmset", "-a", "disablesleep", "1")
    end

    # When AC returns after a power outage, boot automatically. Essential
    # for unattended server operation — otherwise you'd need to physically
    # press the power button after every outage.
    def auto_restart_after_outage
      logger.info "Enabling auto-restart after power failure..."
      cmd.run("sudo", "pmset", "-a", "autorestart", "1")
    end

    # Wake on magic packet from the LAN. Lets you wake the machine from
    # other hosts on your network (`wakeonlan <mac-addr>`) without trips
    # to the hardware.
    def wake_on_network
      logger.info "Enabling wake on network magic packet..."
      cmd.run("sudo", "pmset", "-a", "womp", "1")
    end
  end
end
