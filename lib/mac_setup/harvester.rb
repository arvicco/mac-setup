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
      harvest_git_identity(logger)
      harvest_ssh(logger)
      harvest_gh_token(logger)
      harvest_claude_config(logger)
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
        if write_file("macos_defaults_discovered.yml", YAML.dump(entries), logger)
          logger.info "  + #{entries.length} defaults discovered"
          logger.info "  Review config/personal/macos_defaults_discovered.yml,"
          logger.info "  then merge desired entries into config/macos_defaults.yml"
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
        if write_file("Brewfile.discovered", stdout, logger)
          lines = stdout.lines
          brews = lines.count { |l| l.start_with?("brew ") }
          casks = lines.count { |l| l.start_with?("cask ") }
          mas = lines.count { |l| l.start_with?("mas ") }
          logger.info "  + #{brews} formulae, #{casks} casks, #{mas} mas apps"
          logger.info "  Review config/personal/Brewfile.discovered,"
          logger.info "  then merge desired entries into config/Brewfile"
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
