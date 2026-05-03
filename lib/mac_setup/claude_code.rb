# frozen_string_literal: true

require "fileutils"
require "json"

module MacSetup
  class ClaudeCode < BaseModule
    SETTINGS_SOURCE_DIR = File.join("config", "personal", "claude")
    CLAUDE_DIR          = File.expand_path("~/.claude")
    DOTFILES_CLAUDE_DIR = File.expand_path("~/dotfiles/claude")
    SNIPPET_NAME        = "settings.snippet.json"
    HOOKS_DIR_NAME      = "hooks"
    # settings.json is the shared, checked-in config; settings.local.json
    # is per-machine overrides (often harvested as a convenience but may
    # or may not exist).
    SETTINGS_FILES = %w[settings.json settings.local.json].freeze

    def run
      unless claude_code_installed?
        logger.warn "Claude Code CLI not on PATH — confirm cask 'claude-code' is in Brewfile and Homebrew module ran."
      end
      deploy_settings
      apply_dotfiles_hooks
      logger.info "To authenticate, run: claude"
    end

    private

    def claude_code_installed?
      cmd.success?("command", "-v", "claude")
    end

    def deploy_settings
      source_dir = File.join(MacSetup::ROOT, SETTINGS_SOURCE_DIR)
      return unless File.directory?(source_dir)

      any_source = SETTINGS_FILES.any? { |n| File.exist?(File.join(source_dir, n)) }
      unless any_source
        logger.info "No Claude Code settings found in #{SETTINGS_SOURCE_DIR}/."
        return
      end
      SETTINGS_FILES.each { |name| deploy_setting_file(source_dir, CLAUDE_DIR, name) }
    end

    # Returns :installed / :updated / :unchanged / :missing.
    def deploy_setting_file(source_dir, dest_dir, name)
      source = File.join(source_dir, name)
      return :missing unless File.exist?(source)
      dest = File.join(dest_dir, name)

      if File.exist?(dest) && File.read(dest) == File.read(source)
        logger.info "#{dest} already up to date."
        return :unchanged
      end

      result = :installed
      if File.exist?(dest)
        backup = "#{dest}.bak-#{Time.now.strftime("%Y%m%d-%H%M%S")}"
        FileUtils.cp(dest, backup)
        logger.warn "Backed up existing #{dest} to #{File.basename(backup)}"
        result = :updated
      end

      FileUtils.mkdir_p(dest_dir)
      FileUtils.cp(source, dest)
      logger.success "Installed #{dest}."
      result
    end

    def apply_dotfiles_hooks
      unless File.directory?(DOTFILES_CLAUDE_DIR)
        logger.info "No #{DOTFILES_CLAUDE_DIR}; skipping hooks symlink + snippet merge. Clone your dotfiles repo and re-run."
        return
      end
      link_hooks_dir(DOTFILES_CLAUDE_DIR, CLAUDE_DIR)
      merge_snippet_hooks(File.join(DOTFILES_CLAUDE_DIR, SNIPPET_NAME),
                          File.join(CLAUDE_DIR, "settings.json"))
    end

    # Returns :linked / :missing / :skipped.
    def link_hooks_dir(dotfiles_dir, claude_dir)
      hooks_src = File.join(dotfiles_dir, HOOKS_DIR_NAME)
      unless File.directory?(hooks_src)
        logger.info "No #{HOOKS_DIR_NAME}/ in #{dotfiles_dir}; nothing to link."
        return :missing
      end

      FileUtils.mkdir_p(claude_dir)
      link = File.join(claude_dir, HOOKS_DIR_NAME)

      if File.symlink?(link)
        if File.readlink(link) == hooks_src
          logger.info "#{link} already linked to #{hooks_src}."
          return :linked
        end
        File.unlink(link)
      elsif File.directory?(link)
        # Real directory (not a symlink). Refuse to clobber per CLAUDE.md
        # atomic-actions rule — could contain user-authored hooks the
        # symlink would silently shadow.
        logger.error "#{link} is a real directory, not a symlink. Refusing to clobber — move it aside and re-run."
        return :skipped
      elsif File.exist?(link)
        File.unlink(link)
      end

      File.symlink(hooks_src, link)
      logger.success "Symlinked #{link} -> #{hooks_src}"
      :linked
    end

    # Deep-merges the snippet's `hooks` block into settings.json:
    # per-event hook arrays are concatenated, then deduped by content so
    # re-runs don't grow the array. Backs up settings.json before any
    # change. Returns :merged / :unchanged / :missing / :skipped.
    def merge_snippet_hooks(snippet_path, settings_path)
      return :missing unless File.exist?(snippet_path)

      snippet = parse_json_or_skip(snippet_path)
      return :skipped if snippet.nil?
      snippet_hooks = snippet["hooks"] || {}

      had_settings = File.exist?(settings_path)
      if had_settings
        current = parse_json_or_skip(settings_path)
        return :skipped if current.nil?
      else
        current = {}
      end
      current_hooks = current["hooks"] || {}

      merged_hooks = merge_hooks(current_hooks, snippet_hooks)
      # Two no-op cases:
      #   1. settings.json existed and the merge yields no new entries.
      #   2. settings.json was absent and the snippet has no hooks worth
      #      writing (don't manufacture a stub file the user never had).
      if had_settings && merged_hooks == current_hooks
        logger.info "#{settings_path} already has snippet hooks; no change."
        return :unchanged
      end
      if !had_settings && merged_hooks.empty?
        logger.info "Snippet has no hooks and #{settings_path} is absent; nothing to do."
        return :unchanged
      end

      if had_settings
        backup = "#{settings_path}.bak-#{Time.now.strftime("%Y%m%d-%H%M%S")}"
        FileUtils.cp(settings_path, backup)
        logger.warn "Backed up existing #{settings_path} to #{File.basename(backup)}"
      end

      current["hooks"] = merged_hooks
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, JSON.pretty_generate(current) + "\n")
      logger.success "Merged hooks from #{File.basename(snippet_path)} into #{settings_path}"
      :merged
    end

    # Returns parsed JSON or nil. On parse failure logs an error and
    # returns nil so the caller can :skip rather than crash the run.
    # Atomic-actions rule: refuse to clobber an unfamiliar file.
    def parse_json_or_skip(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      logger.error "#{path} is not valid JSON: #{e.message.lines.first&.strip}"
      logger.error "Refusing to merge — fix or move the file aside, then re-run."
      nil
    end

    def merge_hooks(base, overlay)
      result = base.dup
      overlay.each do |event, entries|
        existing = result[event] || []
        result[event] = (existing + entries).uniq
      end
      result
    end
  end
end
