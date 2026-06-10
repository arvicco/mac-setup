# frozen_string_literal: true

# Release prep: bumps the VERSION file, creates an annotated tag, leaves
# the push to the human. Per maintainer direction the push + GitHub
# release step stays manual — CRPR workflow (per CLAUDE.md) requires
# a code-review pass before push anyway.
#
# Usage:
#   rake release:prepare[0.13.4]    # write VERSION, commit, tag
#   rake release:prepare            # interactive prompt for next version
#
# After running:
#   1. Verify with `git log -1` and `git tag --list 'v*' --sort=-v:refname | head`
#   2. Run /cr to review the bump commit
#   3. git push && git push --tags
#   4. gh release create vX.Y.Z

namespace :release do
  desc "Bump VERSION, commit, tag — push manually afterwards (CRPR)"
  task :prepare, [:version] do |_t, args|
    require "open3"

    repo_root = File.expand_path("..", __dir__)
    version_path = File.join(repo_root, "VERSION")

    new_version = args[:version] || prompt_version(File.read(version_path).strip)
    abort "[release] version must look like X.Y.Z" unless new_version.match?(/\A\d+\.\d+\.\d+\z/)

    File.write(version_path, "#{new_version}\n")
    puts "[release] VERSION → #{new_version}"

    sh_or_die("git", "-C", repo_root, "add", "VERSION")
    sh_or_die("git", "-C", repo_root, "commit", "-m", "Bump VERSION to #{new_version}")
    sh_or_die("git", "-C", repo_root, "tag", "-a", "v#{new_version}", "-m", "Release v#{new_version}")

    puts ""
    puts "[release] Prepared v#{new_version}."
    puts "[release] Next: /cr to review, then `git push && git push --tags`, then `gh release create v#{new_version}`."
  end
end

def prompt_version(current)
  print "Current VERSION is #{current}. New version: "
  $stdin.gets.to_s.strip
end

def sh_or_die(*cmd)
  out, err, status = Open3.capture3(*cmd)
  return out if status.success?
  warn err
  abort "[release] command failed: #{cmd.join(' ')}"
end
