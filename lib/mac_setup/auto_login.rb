# frozen_string_literal: true

require "yaml"

module MacSetup
  class AutoLogin < BaseModule
    CONFIG_FILE      = File.join("config", "personal", "autologin.yml")
    LOGINWINDOW_PLIST = "/Library/Preferences/com.apple.loginwindow"

    def run
      # Opt-in per install. autologin.yml travels inside config/personal.age
      # and is therefore present on every Mac that shares the archive, but
      # only some installs want boot-time auto-login (laptops: no; home
      # server: yes). Require the user to pass --autologin explicitly.
      unless options[:autologin]
        logger.info "Auto-login not enabled (pass --autologin to enable). Skipping."
        return
      end

      path = File.join(MacSetup::ROOT, CONFIG_FILE)
      unless File.exist?(path)
        logger.warn "--autologin passed but #{CONFIG_FILE} is missing. Skipping."
        return
      end

      config   = YAML.safe_load(File.read(path)) || {}
      username = config["username"].to_s.strip
      username = ENV["USER"] if username.empty?
      password = config["password"].to_s

      if password.empty?
        logger.warn "autologin.yml present but `password:` is blank; skipping."
        return
      end

      if already_configured?(username)
        logger.info "Auto-login already set for #{username}."
        return
      end

      # sysadminctl takes the password as a CLI arg — briefly visible in
      # `ps` output. Acceptable for a single-user home-server where no
      # other humans have shell access; noting the limitation.
      logger.info "Enabling auto-login for #{username}..."
      _out, err, status = cmd.run(
        "sudo", "sysadminctl", "-autologin", "set",
        "-userName", username, "-password", password,
        abort_on_fail: false, quiet: true,
      )
      if status.success?
        logger.success "Auto-login enabled for #{username}."
      else
        logger.error "sysadminctl failed: #{err.strip}"
      end
    end

    private

    def already_configured?(username)
      # sudo for robustness: autoLoginUser on the system loginwindow plist
      # is world-readable by default on current macOS, but hardened or
      # MDM-managed machines restrict it. Running under sudo avoids the
      # false-negative path where the read fails silently and we then
      # re-invoke sysadminctl every run.
      stdout, _stderr, status = cmd.run(
        "sudo", "defaults", "read", LOGINWINDOW_PLIST, "autoLoginUser", quiet: true,
      )
      status.success? && stdout.strip == username
    end
  end
end
