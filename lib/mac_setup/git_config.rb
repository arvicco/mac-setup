# frozen_string_literal: true

module MacSetup
  class GitConfig < BaseModule
    def run
      configure_identity
      set_config "init.defaultBranch", "main"
      set_config "pull.rebase", "true"
      set_config "core.editor", "vim"
    end

    private

    def configure_identity
      current_name = get_config("user.name")
      current_email = get_config("user.email")

      name = prompt("Git name", current_name)
      set_config("user.name", name) unless name.empty?

      email = prompt("Git email", current_email)
      set_config("user.email", email) unless email.empty?
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
      stdout, _, status = cmd.run("git config --global #{key}", quiet: true)
      status.success? ? stdout.strip : ""
    end

    def set_config(key, value)
      logger.info "git config --global #{key} = #{value}"
      cmd.run("git config --global #{key} \"#{value}\"")
    end
  end
end
