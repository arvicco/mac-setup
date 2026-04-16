# frozen_string_literal: true

require_relative "mac_setup/utils/logger"
require_relative "mac_setup/utils/command_runner"
require_relative "mac_setup/utils/file_editor"
require_relative "mac_setup/base_module"
require_relative "mac_setup/hostname"
require_relative "mac_setup/homebrew"
require_relative "mac_setup/cask"
require_relative "mac_setup/macos_defaults"
require_relative "mac_setup/git_config"
require_relative "mac_setup/shell"
require_relative "mac_setup/terminal_app"
require_relative "mac_setup/ssh"
require_relative "mac_setup/node"
require_relative "mac_setup/claude_code"
require_relative "mac_setup/runner"

module MacSetup
  VERSION = "0.1.0"
  ROOT = File.expand_path("..", __dir__)
end
