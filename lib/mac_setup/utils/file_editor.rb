# frozen_string_literal: true

module MacSetup
  module Utils
    module FileEditor
      module_function

      # Ensure `line` is present in `path`. If the file doesn't exist it's
      # created. If `line` (exact substring match) is already in the file,
      # returns false without modifying it. Otherwise appends `line` on its
      # own line (with a leading blank line if the file is non-empty and
      # doesn't already end in "\n\n") and returns true.
      #
      # Idempotent: safe to call repeatedly.
      def ensure_line_in_file(path, line)
        path = File.expand_path(path)
        existing = File.exist?(path) ? File.read(path) : ""
        return false if existing.include?(line)

        File.open(path, "a") do |f|
          f.puts "" unless existing.empty? || existing.end_with?("\n\n")
          f.puts line
        end
        true
      end

      # Ensure a multi-line block is present in `path`, identified by `marker`
      # (a unique substring that will appear somewhere in the block). If the
      # marker is already present, returns false. Otherwise appends the block.
      def ensure_block_in_file(path, marker, block)
        path = File.expand_path(path)
        existing = File.exist?(path) ? File.read(path) : ""
        return false if existing.include?(marker)

        File.open(path, "a") do |f|
          f.puts "" unless existing.empty? || existing.end_with?("\n\n")
          f.puts block
        end
        true
      end
    end
  end
end
