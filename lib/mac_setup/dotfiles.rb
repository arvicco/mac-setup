# frozen_string_literal: true

require "yaml"

module MacSetup
  class Dotfiles < BaseModule
    CONFIG_FILE = File.join("config", "personal", "dotfiles.yml")
    DEFAULT_PATH = File.expand_path("~/dotfiles")

    def run
      unless File.exist?(config_path)
        logger.info "No #{CONFIG_FILE}; skipping dotfiles."
        return
      end

      repo = load_repo
      unless repo
        logger.error "#{CONFIG_FILE} is missing 'repo:' key."
        return
      end

      target = dotfiles_path
      if File.exist?(target)
        if File.directory?(File.join(target, ".git"))
          pull(target)
        else
          logger.error "#{target} exists but is not a git repo. Refusing to clobber — move it aside and re-run."
        end
      else
        clone(repo, target)
      end
    end

    private

    def config_path
      File.join(MacSetup::ROOT, CONFIG_FILE)
    end

    def dotfiles_path
      DEFAULT_PATH
    end

    def load_repo
      data = YAML.load_file(config_path)
      return nil unless data.is_a?(Hash)
      repo = data["repo"]
      repo.is_a?(String) && !repo.strip.empty? ? repo.strip : nil
    end

    def clone(repo, target)
      logger.info "Cloning #{repo} into #{target}..."
      cmd.run("git", "clone", repo, target, stream: true)
    end

    def pull(target)
      logger.info "Updating #{target} (git pull --ff-only)..."
      cmd.run("git", "-C", target, "pull", "--ff-only", stream: true)
    end
  end
end
