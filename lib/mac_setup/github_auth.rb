# frozen_string_literal: true

require "socket"

module MacSetup
  class GithubAuth < BaseModule
    TOKEN_FILE = File.join("config", "personal", "gh_token")
    GITHUB_KEY = File.expand_path("~/.ssh/id_ed25519_github.pub")

    def run
      token_path = File.join(MacSetup::ROOT, TOKEN_FILE)
      unless File.exist?(token_path)
        logger.info "No #{TOKEN_FILE}; skipping GitHub auth."
        return
      end

      unless cmd.success?("which", "gh")
        logger.warn "gh CLI not found — ensure Brewfile installed it."
        return
      end

      return unless ensure_gh_auth(token_path)
      if options[:github_ssh]
        ensure_ssh_key_uploaded
      else
        logger.info "Using HTTPS for github.com (default). Skipping SSH key upload. Pass --github-ssh to enable."
      end
    end

    private

    # Returns true if gh is authenticated after this call, false if not
    # (so the caller can skip downstream gh-dependent work).
    def ensure_gh_auth(token_path)
      if cmd.success?("gh", "auth", "status")
        logger.info "gh is already authenticated; skipping token login."
        return true
      end
      logger.info "Authenticating gh CLI with token from #{TOKEN_FILE}..."
      token = File.read(token_path).strip
      # gh auth login --with-token reads from stdin. Use Open3 directly so
      # the token isn't visible in process args (which `ps` shows world-wide).
      require "open3"
      stdout, stderr, status = Open3.capture3(
        "gh", "auth", "login", "--with-token",
        stdin_data: token,
      )
      if status.success?
        logger.success "gh authenticated."
        return true
      end
      logger.error "gh auth login failed: #{stderr.strip}"
      logger.info stdout.strip unless stdout.strip.empty?
      false
    end

    def ensure_ssh_key_uploaded
      unless File.exist?(GITHUB_KEY)
        logger.warn "No #{GITHUB_KEY} to upload — SSH module should have generated it."
        return
      end
      pub_key = File.read(GITHUB_KEY).strip

      # `gh ssh-key list` output includes the full key material; match by
      # the base64 part (second whitespace-separated field) which is the
      # stable identifier across title changes.
      list_out, _, list_status = cmd.run("gh", "ssh-key", "list", quiet: true)
      key_body = pub_key.split(/\s+/)[1].to_s
      if list_status.success? && !key_body.empty? && list_out.include?(key_body)
        logger.info "GitHub already has this SSH key; skipping upload."
        return
      end
      unless list_status.success?
        logger.warn "gh ssh-key list failed — gh_token may lack the `admin:public_key` scope. Continuing to try upload anyway."
      end

      title = "mac-setup: #{Socket.gethostname}"
      logger.info "Uploading #{GITHUB_KEY} to GitHub as '#{title}'..."
      cmd.run("gh", "ssh-key", "add", GITHUB_KEY, "--title", title, abort_on_fail: false)
    end
  end
end
