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
    OAUTH_TOKEN_URL = "https://api.tailscale.com/api/v2/oauth/token"
    OAUTH_KEY_URL   = "https://api.tailscale.com/api/v2/tailnet/-/keys"
    # Auth keys only need to live long enough for `tailscale up` to consume
    # them. 5 min gives generous headroom for slow networks.
    KEY_TTL_SECONDS = 300

    def run
      config_path = File.join(MacSetup::ROOT, CONFIG_FILE)
      unless File.exist?(config_path)
        logger.info "No #{CONFIG_FILE}; skipping Tailscale setup."
        return
      end

      unless File.executable?(TAILSCALE)
        logger.warn "#{TAILSCALE} not found — ensure Brewfile installed tailscale."
        return
      end

      if already_connected?
        logger.info "Tailscale already running (BackendState=Running); skipping."
        return
      end

      config = YAML.safe_load(File.read(config_path)) || {}
      client_id     = config.fetch("oauth_client_id")
      client_secret = config.fetch("oauth_client_secret")
      tags          = config["tags"] || []
      extra_args    = config["extra_up_args"] || []
      hostname      = config["hostname"] || current_hostname

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

    private

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
