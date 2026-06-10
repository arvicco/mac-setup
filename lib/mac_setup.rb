# frozen_string_literal: true

require_relative "mac_setup/utils/logger"
require_relative "mac_setup/utils/command_runner"
require_relative "mac_setup/utils/file_editor"
require_relative "mac_setup/base_module"
require_relative "mac_setup/sudo_session"
require_relative "mac_setup/module_selector"
require_relative "mac_setup/hostname"
require_relative "mac_setup/homebrew"
require_relative "mac_setup/homebrew_personal"
require_relative "mac_setup/karabiner"
require_relative "mac_setup/keyboard_layouts"
require_relative "mac_setup/keyboard_shortcuts"
require_relative "mac_setup/default_browser"
require_relative "mac_setup/dock"
require_relative "mac_setup/macos_defaults"
require_relative "mac_setup/git_config"
require_relative "mac_setup/secrets"
require_relative "mac_setup/security"
require_relative "mac_setup/shell"
require_relative "mac_setup/iterm2"
require_relative "mac_setup/rclone"
require_relative "mac_setup/ssh"
require_relative "mac_setup/github_auth"
require_relative "mac_setup/tailscale"
require_relative "mac_setup/node"
require_relative "mac_setup/auto_login"
require_relative "mac_setup/power_management"
require_relative "mac_setup/dotfiles"
require_relative "mac_setup/claude_code"
require_relative "mac_setup/harvester"
require_relative "mac_setup/runner"

module MacSetup
  ROOT = File.expand_path("..", __dir__)
  # Single source of truth. The release task (rake release:prepare) writes
  # this file; bin/setup logs the value at startup so triage from log files
  # always shows the deployed version. Fallback handles cases where this
  # file isn't present (vendored copies, gem-style installs — none today,
  # but cheap insurance).
  VERSION = begin
    File.read(File.join(ROOT, "VERSION")).strip
  rescue Errno::ENOENT, Errno::EACCES
    "0.0.0+unknown"
  end
end
