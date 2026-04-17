# frozen_string_literal: true

require "yaml"

module MacSetup
  class GitConfig < BaseModule
    IDENTITY_FILE = File.join("config", "personal", "git_identity.yml")

    def run
      configure_identity
      set_config "init.defaultBranch", "main"
      set_config "pull.rebase", "true"
      set_config "core.editor", "vim"
    end

    private

    def configure_identity
      identity = load_identity
      current_name = get_config("user.name")
      current_email = get_config("user.email")

      name = options[:git_name] || identity["name"] || prompt("Git name", current_name)
      set_config("user.name", name) unless name.empty?

      email = options[:git_email] || identity["email"] || prompt("Git email", current_email)
      set_config("user.email", email) unless email.empty?
    end

    def load_identity
      path = File.join(MacSetup::ROOT, IDENTITY_FILE)
      return {} unless File.exist?(path)

      data = YAML.safe_load(File.read(path))
      logger.info "Read git identity from #{IDENTITY_FILE}."
      data || {}
    end

    def prompt(label, current)
      if current.empty?
        print "#{label}: "
      else
        print "#{label} (#{current}): "
      end
      input = $stdin.gets
      value = input ? input.chomp.strip : ""
      value.empty? ? current : value
    end

    def get_config(key)
      stdout, _, status = cmd.run("git", "config", "--global", key, quiet: true)
      status.success? ? stdout.strip : ""
    end

    def set_config(key, value)
      logger.info "git config --global #{key} = #{value}"
      cmd.run("git", "config", "--global", key, value)
    end
  end
end
