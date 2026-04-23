# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "yaml"

module MacSetup
  class Tailscale < BaseModule
    CONFIG_FILE = File.join("config", "personal", "tailscale.yml")
    TAILSCALE   = "/opt/homebrew/bin/tailscale"
    TAILSCALED  = "/opt/homebrew/bin/tailscaled"
    CASK_APP    = "/Applications/Tailscale.app"
    OAUTH_TOKEN_URL = "https://api.tailscale.com/api/v2/oauth/token"
    OAUTH_KEY_URL   = "https://api.tailscale.com/api/v2/tailnet/-/keys"
    # Auth keys only need to live long enough for `tailscale up` to consume
    # them. 5 min gives generous headroom for slow networks.
    KEY_TTL_SECONDS = 300

    # Two legal modes, picked per-machine by which package the user put in
    # their personal Brewfile:
    #   - formula (`brew "tailscale"`) — headless daemon for always-on servers
    #   - cask    (`cask "tailscale-app"`) — GUI app for admin workstations
    # Running both simultaneously registers the Mac twice in the tailnet
    # (one tagged, one under the personal account) and the CLI hits whichever
    # socket bound first, producing a client/server version-mismatch warning.
    def run
      formula = formula_installed?
      cask    = cask_installed?

      if formula && cask
        logger.error "Both tailscale formula and tailscale-app cask are installed."
        logger.error "They conflict: each registers the Mac as a separate device in your tailnet"
        logger.error "(visible as two entries in the admin console, e.g. `noto` + `noto-1`), and"
        logger.error "the CLI hits whichever daemon grabbed the control socket first."
        logger.error "Pick one in config/personal/Brewfile and uninstall the other:"
        logger.error "  headless server → keep `brew \"tailscale\"`, `brew uninstall --cask tailscale-app`"
        logger.error "  admin workstation → keep `cask \"tailscale-app\"`, `brew uninstall tailscale`"
        return
      end

      if cask
        logger.info "Tailscale GUI app detected; sign in via the menu bar. Skipping headless setup."
        return
      end

      unless formula
        if config_present?
          logger.warn "#{CONFIG_FILE} exists but no tailscale package is installed."
          logger.warn "Add `brew \"tailscale\"` (headless) or `cask \"tailscale-app\"` (GUI) to config/personal/Brewfile."
        else
          logger.info "No #{CONFIG_FILE} and no tailscale package installed; skipping Tailscale setup."
        end
        return
      end

      unless config_present?
        logger.info "No #{CONFIG_FILE}; skipping Tailscale setup."
        return
      end

      if already_connected?
        logger.info "Tailscale already running (BackendState=Running); skipping."
        return
      end

      config = YAML.safe_load(File.read(config_path)) || {}
      client_id     = config["oauth_client_id"]
      client_secret = config["oauth_client_secret"]
      tags          = config["tags"] || []
      extra_args    = config["extra_up_args"] || []
      hostname      = config["hostname"] || current_hostname

      missing = missing_or_placeholder(
        "oauth_client_id" => client_id,
        "oauth_client_secret" => client_secret,
      )
      unless missing.empty?
        logger.warn "#{CONFIG_FILE} has unfilled fields: #{missing.join(", ")}. Skipping Tailscale setup."
        logger.info "See README Tailscale section for how to create an OAuth client and fill these in."
        return
      end

      if tags.empty?
        logger.error "tailscale.yml must list at least one tag under `tags:` — OAuth-minted keys require tags."
        return
      end

      install_system_daemon
      access_token = exchange_oauth_token(client_id, client_secret)
      auth_key = mint_auth_key(access_token, tags)
      tailscale_up(auth_key, hostname, extra_args)
    ensure
      # Make sure the fresh key doesn't linger in memory longer than
      # necessary. tailscale up consumes single-use keys; best-effort.
      auth_key.clear if defined?(auth_key) && auth_key.is_a?(String)
    end

    # Return the keys whose value is missing, blank, or still the
    # REPLACE_ME sentinel from the harvester template. Used to bail
    # cleanly when the user has the template but hasn't pasted in
    # real OAuth creds yet — better than crashing deep inside HTTP.
    def missing_or_placeholder(fields)
      fields.each_with_object([]) do |(name, value), missing|
        missing << name if value.nil? || value.to_s.strip.empty? || value.to_s.strip == "REPLACE_ME"
      end
    end

    private

    def formula_installed?
      File.executable?(TAILSCALE)
    end

    def cask_installed?
      File.directory?(CASK_APP)
    end

    def config_path
      File.join(MacSetup::ROOT, CONFIG_FILE)
    end

    def config_present?
      File.exist?(config_path)
    end

    def already_connected?
      stdout, _stderr, status = cmd.run(TAILSCALE, "status", "--json", quiet: true)
      return false unless status.success?
      JSON.parse(stdout)["BackendState"] == "Running"
    rescue JSON::ParserError
      false
    end

    # Installs tailscaled as a LaunchDaemon so the node stays connected
    # without a GUI login. Idempotent: re-running when already installed
    # is safe (prints a message and exits 0).
    def install_system_daemon
      return if launchdaemon_installed?
      logger.info "Installing tailscaled as system daemon..."
      cmd.run("sudo", TAILSCALED, "install-system-daemon", abort_on_fail: true)
    end

    def launchdaemon_installed?
      File.exist?("/Library/LaunchDaemons/com.tailscale.tailscaled.plist")
    end

    def exchange_oauth_token(client_id, client_secret)
      logger.info "Exchanging OAuth client credentials for access token..."
      uri = URI(OAUTH_TOKEN_URL)
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(
        "client_id"     => client_id,
        "client_secret" => client_secret,
        "scope"         => "auth_keys",
      )
      parsed = JSON.parse(http_request(uri, req, "OAuth token exchange"))
      logger.info "Got access token (expires in #{parsed["expires_in"]}s)."
      parsed.fetch("access_token")
    end

    def mint_auth_key(access_token, tags)
      logger.info "Minting single-use auth key (tags=#{tags.join(",")}, ttl=#{KEY_TTL_SECONDS}s)..."
      uri = URI(OAUTH_KEY_URL)
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      req["Content-Type"]  = "application/json"
      req.body = JSON.generate(build_key_spec(tags))
      body = http_request(uri, req, "Auth key creation")
      JSON.parse(body).fetch("key")
    end

    # Single-use, persistent (non-ephemeral), pre-approved so admin
    # doesn't have to click. Tagged per config.
    def build_key_spec(tags)
      {
        "capabilities" => {
          "devices" => {
            "create" => {
              "reusable"      => false,
              "ephemeral"     => false,
              "preauthorized" => true,
              "tags"          => tags,
            },
          },
        },
        "expirySeconds" => KEY_TTL_SECONDS,
      }
    end

    def tailscale_up(auth_key, hostname, extra_args)
      logger.info "Running tailscale up (hostname=#{hostname})..."
      args = [
        "sudo", TAILSCALE, "up",
        "--auth-key=#{auth_key}",
        "--hostname=#{hostname}",
        "--ssh",
        "--accept-dns",
        *extra_args,
      ]
      # `quiet: true` suppresses CommandRunner's argv echo — otherwise the
      # full auth key lands in the terminal, controller SSH log, and any
      # CI capture. We print a redacted version instead.
      redacted = args.map { |a| a.start_with?("--auth-key=") ? "--auth-key=<redacted>" : a }
      logger.info "$ #{redacted.join(" ")}"
      _out, err, status = cmd.run(*args, quiet: true, abort_on_fail: false)
      unless status.success?
        logger.error "tailscale up failed: #{err.strip}"
        raise "tailscale up exited #{status.exitstatus}"
      end
      logger.success "Tailscale connected as '#{hostname}'."
    end

    def http_request(uri, req, label)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.open_timeout = 10
        http.read_timeout = 30
        res = http.request(req)
        unless res.is_a?(Net::HTTPSuccess)
          raise "#{label} failed: HTTP #{res.code} — #{res.body}"
        end
        res.body
      end
    end

    def current_hostname
      stdout, _, status = cmd.run("scutil", "--get", "LocalHostName", quiet: true)
      status.success? ? stdout.strip : "mac"
    end
  end
end
