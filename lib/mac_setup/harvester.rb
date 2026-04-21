# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "yaml"

module MacSetup
  class Harvester

    # Dotfiles to look for in $HOME. Add/remove as needed.
    DOTFILES = %w[
      .zshrc
      .zprofile
      .zshenv
      .zlogin
      .zlogout
      .bashrc
      .bash_profile
      .vimrc
      .tmux.conf
      .gitignore_global
      .inputrc
      .curlrc
      .wgetrc
      .editorconfig
    ].freeze

    # Directories under $HOME to harvest whole. Paths may be nested
    # (e.g. ".config/nvim") — Shell walks the harvested tree file-by-
    # file on deploy, merging into the target rather than replacing
    # whole directories, so sibling subtrees not in this list stay
    # intact.
    # Deliberately excluded — managed by their own modules or contain
    # per-machine auth state:
    #   .config/rclone      — Rclone module
    #   .config/karabiner   — Karabiner module
    #   .config/gh          — auth tokens, per-machine
    DOTDIRS = %w[
      .zsh
      .config/git
      .config/nvim
      .config/fish
      .config/starship
      .config/alacritty
      .config/wezterm
      .config/kitty
      .config/tmux
      .config/zsh
    ].freeze

    # macOS defaults we care about. Each: [domain, key, type].
    # type is used to write the correct macos_defaults.yml entry.
    INTERESTING_DEFAULTS = [
      # Dock
      ["com.apple.dock", "autohide", "bool"],
      ["com.apple.dock", "tilesize", "int"],
      ["com.apple.dock", "show-recents", "bool"],
      ["com.apple.dock", "minimize-to-application", "bool"],
      ["com.apple.dock", "mineffect", "string"],
      ["com.apple.dock", "orientation", "string"],
      ["com.apple.dock", "launchanim", "bool"],
      # Finder
      ["com.apple.finder", "AppleShowAllFiles", "bool"],
      ["com.apple.finder", "ShowPathbar", "bool"],
      ["com.apple.finder", "ShowStatusBar", "bool"],
      ["com.apple.finder", "FXPreferredViewStyle", "string"],
      ["com.apple.finder", "FXDefaultSearchScope", "string"],
      ["com.apple.finder", "_FXShowPosixPathInTitle", "bool"],
      ["com.apple.finder", "FXEnableExtensionChangeWarning", "bool"],
      # Global
      ["NSGlobalDomain", "KeyRepeat", "int"],
      ["NSGlobalDomain", "InitialKeyRepeat", "int"],
      ["NSGlobalDomain", "AppleShowAllExtensions", "bool"],
      ["NSGlobalDomain", "NSAutomaticSpellingCorrectionEnabled", "bool"],
      ["NSGlobalDomain", "NSAutomaticCapitalizationEnabled", "bool"],
      ["NSGlobalDomain", "NSAutomaticPeriodSubstitutionEnabled", "bool"],
      ["NSGlobalDomain", "ApplePressAndHoldEnabled", "bool"],
      # Screenshots
      ["com.apple.screencapture", "location", "string"],
      ["com.apple.screencapture", "type", "string"],
      ["com.apple.screencapture", "disable-shadow", "bool"],
      # Menu bar clock
      ["com.apple.menuextra.clock", "DateFormat", "string"],
      # Trackpad
      ["com.apple.AppleMultitouchTrackpad", "Clicking", "bool"],
      ["com.apple.AppleMultitouchTrackpad", "TrackpadThreeFingerDrag", "bool"],
    ].freeze

    def initialize(argv = [])
      @argv = argv
      @options = {}
      parse_options
    end

    def run
      if @options[:help]
        puts @parser
        return
      end

      logger = Utils::Logger.new
      logger.info "Harvesting personal config from this Mac..."
      logger.info "Output: #{output_dir}/"
      logger.info ""

      FileUtils.mkdir_p(output_dir)

      harvest_dotfiles(logger)
      harvest_dotdirs(logger)
      harvest_git_identity(logger)
      harvest_ssh(logger)
      harvest_gh_token(logger)
      harvest_claude_config(logger)
      harvest_rclone(logger)
      harvest_iterm2(logger)
      harvest_autologin_template(logger)
      harvest_tailscale_template(logger)
      harvest_macos_defaults(logger)
      harvest_brewfile(logger)
      harvest_keyboard(logger)

      logger.info ""
      logger.success "Harvest complete. Review files in config/personal/, then pack:"
      logger.info "  tar cz -C config/personal . | age -p > config/personal.age"
      logger.info "  git add config/personal.age && git commit -m 'Update personal config'"
    end

    private

    def output_dir
      @output_dir ||= File.join(MacSetup::ROOT, "config", "personal")
    end

    def parse_options
      @parser = OptionParser.new do |opts|
        opts.banner = "Usage: harvest [options]"
        opts.on("-f", "--force", "Overwrite existing files in config/personal/") do
          @options[:force] = true
        end
        opts.on("-h", "--help", "Show this help") do
          @options[:help] = true
        end
      end
      @parser.parse!(@argv)
    end

    def write_file(path, content, logger)
      full = File.join(output_dir, path)
      if File.exist?(full) && !@options[:force]
        logger.warn "  #{path} already exists (use --force to overwrite)"
        return false
      end
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
      true
    end

    def copy_file(src, dest_relative, logger)
      full_dest = File.join(output_dir, dest_relative)
      if File.exist?(full_dest) && !@options[:force]
        logger.warn "  #{dest_relative} already exists (use --force to overwrite)"
        return false
      end
      FileUtils.mkdir_p(File.dirname(full_dest))
      FileUtils.cp(src, full_dest)
      true
    end

    # ---------------------------------------------------------------- Dotfiles

    def harvest_dotfiles(logger)
      logger.info "Dotfiles:"
      found = 0
      DOTFILES.each do |name|
        src = File.expand_path("~/#{name}")
        if File.exist?(src)
          if copy_file(src, "dotfiles/#{name}", logger)
            logger.info "  + ~/#{name}"
            found += 1
          end
        end
      end
      logger.info "  (#{found} dotfiles collected)" if found > 0
      logger.info "  (none found)" if found == 0
      logger.info ""
    end

    # ---------------------------------------------------------------- Dotdirs

    def harvest_dotdirs(logger)
      logger.info "Dotdirs:"
      found = 0
      DOTDIRS.each do |name|
        src = File.expand_path("~/#{name}")
        next unless File.directory?(src)

        # Skip if it looks like a git repo — that's cloned tooling, not
        # config, and checking in the full .git tree would bloat the
        # encrypted archive substantially.
        if File.exist?(File.join(src, ".git"))
          logger.info "  (skipping ~/#{name}: looks like a git repo)"
          next
        end

        dest = File.join(output_dir, "dotfiles", name)
        if File.exist?(dest) && !@options[:force]
          logger.warn "  dotfiles/#{name}/ already exists (use --force to overwrite)"
          next
        end
        FileUtils.rm_rf(dest) if File.exist?(dest)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp_r(src, dest)
        logger.info "  + ~/#{name}/"
        found += 1
      end
      logger.info "  (#{found} directories collected)" if found > 0
      logger.info "  (none found)" if found == 0
      logger.info ""
    end

    # ---------------------------------------------------------------- Git

    def harvest_git_identity(logger)
      logger.info "Git identity:"
      name, = Open3.capture3("git", "config", "--global", "user.name")
      email, = Open3.capture3("git", "config", "--global", "user.email")
      name = name.strip
      email = email.strip

      if name.empty? && email.empty?
        logger.info "  (no global git identity configured)"
      else
        identity = {}
        identity["name"] = name unless name.empty?
        identity["email"] = email unless email.empty?
        if write_file("git_identity.yml", YAML.dump(identity), logger)
          logger.info "  + name: #{name}" unless name.empty?
          logger.info "  + email: #{email}" unless email.empty?
        end
      end
      logger.info ""
    end

    # ---------------------------------------------------------------- SSH

    def harvest_ssh(logger)
      logger.info "SSH config:"
      ssh_config = File.expand_path("~/.ssh/config")
      if File.exist?(ssh_config)
        if copy_file(ssh_config, "ssh_config", logger)
          logger.info "  + ~/.ssh/config"
        end
      else
        logger.info "  (no ~/.ssh/config found)"
      end

      known_hosts = File.expand_path("~/.ssh/known_hosts")
      if File.exist?(known_hosts)
        if copy_file(known_hosts, "known_hosts", logger)
          logger.info "  + ~/.ssh/known_hosts"
        end
      end
      logger.info ""
    end

    # ---------------------------------------------------------------- GitHub

    def harvest_gh_token(logger)
      logger.info "GitHub CLI:"
      token, _, status = Open3.capture3("gh", "auth", "token")
      if status.success? && !token.strip.empty?
        if write_file("gh_token", token.strip + "\n", logger)
          logger.info "  + token: #{token.strip[0..7]}****"
        end
      else
        logger.info "  (gh not authenticated — run 'gh auth login' first)"
      end
      logger.info ""
    end

    # ---------------------------------------------------------------- Claude Code

    def harvest_claude_config(logger)
      logger.info "Claude Code config:"
      found = 0

      settings = File.expand_path("~/.claude/settings.json")
      if File.exist?(settings)
        if copy_file(settings, "claude/settings.json", logger)
          logger.info "  + ~/.claude/settings.json"
          found += 1
        end
      end

      settings_local = File.expand_path("~/.claude/settings.local.json")
      if File.exist?(settings_local)
        if copy_file(settings_local, "claude/settings.local.json", logger)
          logger.info "  + ~/.claude/settings.local.json"
          found += 1
        end
      end

      logger.info "  (no Claude Code config found)" if found == 0
      logger.info ""
    end

    # ---------------------------------------------------------------- Rclone

    def harvest_rclone(logger)
      logger.info "rclone config:"
      source = File.expand_path("~/.config/rclone/rclone.conf")
      if File.exist?(source)
        if copy_file(source, "rclone.conf", logger)
          logger.info "  + rclone.conf"
        end
      else
        logger.info "  (no ~/.config/rclone/rclone.conf — run `rclone config` first)"
      end
      logger.info ""
    end

    # ---------------------------------------------------------------- iTerm2

    def harvest_iterm2(logger)
      logger.info "iTerm2 prefs:"
      source = File.expand_path("~/Library/Preferences/com.googlecode.iterm2.plist")
      if File.exist?(source)
        if copy_file(source, "iterm2.plist", logger)
          logger.info "  + iterm2.plist"
        end
      else
        logger.info "  (no iTerm2 plist found — launch iTerm2 at least once)"
      end
      logger.info ""
    end

    # ---------------------------------------------------------------- Auto-login
    #
    # Login passwords can't be harvested from the live Mac — macOS never
    # exposes them. Emit a template so the user knows the shape.

    def harvest_autologin_template(logger)
      logger.info "Auto-login (template):"
      path = File.join(output_dir, "autologin.yml")
      if File.exist?(path)
        logger.info "  autologin.yml already present — leaving as-is"
        logger.info ""
        return
      end
      user = ENV["USER"] || "admin"
      template = <<~YAML
        # Enable auto-login at boot for this user. Useful on a home-server
        # Mac that must come up unattended after a power outage (pair with
        # `pmset autorestart 1`, which PowerManagement sets).
        #
        # This file ships inside config/personal.age — present on every
        # Mac that shares the archive. To actually apply it, pass the
        # --autologin flag to bin/setup on the Mac where you want boot-
        # time auto-login; the module is a no-op without the flag.
        #
        # SECURITY NOTES:
        # - The password below is stored age-encrypted in config/personal.age,
        #   but sysadminctl also writes it (obfuscated, not encrypted) to
        #   /etc/kcpassword, which is readable by root.
        # - FileVault must be OFF for auto-login to actually take effect
        #   (FileVault requires the password to unlock the disk at boot).
        # - sysadminctl briefly exposes the password in `ps` argv during setup.
        # Acceptable for a single-user server; not for a multi-user machine.
        username: #{user}
        password: REPLACE_ME
      YAML
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, template)
      File.chmod(0o600, path)
      logger.info "  + autologin.yml (template — fill in login password, or delete the file to skip)"
      logger.info ""
    end

    # ---------------------------------------------------------------- Tailscale
    #
    # Nothing to harvest from the live system — OAuth client credentials
    # live only in Tailscale's admin panel. We emit a template so the
    # user knows the expected shape and can fill in values by hand.

    def harvest_tailscale_template(logger)
      logger.info "Tailscale (template):"
      path = File.join(output_dir, "tailscale.yml")
      # Templates are scaffolded once and filled in by hand; there is no
      # live source to re-harvest. Never overwrite, even with --force —
      # that would clobber OAuth creds the user has already pasted in.
      if File.exist?(path)
        logger.info "  tailscale.yml already present — leaving as-is"
        logger.info ""
        return
      end
      template = <<~YAML
        # OAuth client credentials for joining the tailnet from bin/setup.
        # Create at https://login.tailscale.com/admin/settings/oauth with
        # scope: auth_keys (write). Then define a tag in your ACL policy:
        #   "tagOwners": { "tag:home-server": ["autogroup:admin"] }
        # The Tailscale module exchanges these creds for a single-use auth
        # key at setup time; keys never persist on disk.
        oauth_client_id: REPLACE_ME
        oauth_client_secret: REPLACE_ME
        tags:
          - tag:home-server

        # Optional overrides:
        # hostname: my-machine           # defaults to scutil --get LocalHostName
        # extra_up_args:
        #   - --accept-routes            # use tailnet subnet routers
      YAML
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, template)
      logger.info "  + tailscale.yml (template — fill in OAuth creds)"
      logger.info ""
    end

    # ---------------------------------------------------------------- macOS defaults

    def harvest_macos_defaults(logger)
      logger.info "macOS defaults (#{INTERESTING_DEFAULTS.length} keys checked):"
      entries = []

      INTERESTING_DEFAULTS.each do |domain, key, type|
        stdout, _, status = Open3.capture3("defaults", "read", domain, key)
        next unless status.success?

        raw = stdout.strip
        value = coerce_value(raw, type)
        entries << { "domain" => domain, "key" => key, "type" => type, "value" => value }
      end

      if entries.empty?
        logger.info "  (no interesting defaults found)"
      else
        # config/personal/macos_defaults.yml serves as the live overlay
        # that MacosDefaults applies on top of the core-tracked yml.
        # Review + prune the file before packing personal.age — anything
        # left here is applied on every install that decrypts the archive.
        # Entries colliding with core are dropped at apply time (core wins).
        if write_file("macos_defaults.yml", YAML.dump(entries), logger)
          logger.info "  + #{entries.length} defaults discovered"
          logger.info "  Review config/personal/macos_defaults.yml (OVERLAY — applied after core);"
          logger.info "  prune entries you don't want carried across every install before packing."
        end
      end
      logger.info ""
    end

    def coerce_value(raw, type)
      case type
      when "bool"
        # defaults read returns "1"/"0" or "true"/"false"
        %w[1 true].include?(raw.downcase) ? true : false
      when "int"
        raw.to_i
      when "float"
        raw.to_f
      else
        raw
      end
    end

    # ---------------------------------------------------------------- Brewfile

    def harvest_brewfile(logger)
      logger.info "Brewfile:"
      stdout, _, status = Open3.capture3("brew", "bundle", "dump", "--file=-")
      if status.success? && !stdout.strip.empty?
        # config/personal/Brewfile is the live overlay — Homebrew runs
        # `brew bundle` on it after the core Brewfile. Review + prune
        # before packing personal.age; unreviewed cruft gets installed
        # on every new Mac that decrypts this archive.
        if write_file("Brewfile", stdout, logger)
          lines = stdout.lines
          brews = lines.count { |l| l.start_with?("brew ") }
          casks = lines.count { |l| l.start_with?("cask ") }
          mas = lines.count { |l| l.start_with?("mas ") }
          logger.info "  + #{brews} formulae, #{casks} casks, #{mas} mas apps"
          logger.info "  Review config/personal/Brewfile (OVERLAY — applied after core);"
          logger.info "  prune packages you don't want carried across every install before packing."
        end
      else
        logger.info "  (brew not installed or no packages found)"
      end
      logger.info ""
    end

    # ---------------------------------------------------------------- Keyboard

    def harvest_keyboard(logger)
      logger.info "Keyboard remapping:"
      stdout, _, status = Open3.capture3(
        "hidutil", "property", "--get", "UserKeyMapping"
      )
      if status.success? && !stdout.strip.empty? && stdout.strip != "(null)" && stdout.strip != "()"
        if write_file("keyboard_remapping.json", stdout, logger)
          logger.info "  + hidutil UserKeyMapping discovered"
          logger.info "  Review config/personal/keyboard_remapping.json"
        end
      else
        logger.info "  (no keyboard remapping active)"
      end
      logger.info ""
    end
  end
end
