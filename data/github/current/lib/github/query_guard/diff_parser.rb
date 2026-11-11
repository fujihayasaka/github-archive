# typed: true
# frozen_string_literal: true

module GitHub
  module QueryGuard
    class DiffParser
      DIFF_FILE = /\Adiff --git .* b\/(.+)/
      HUNK_HEADER = /\A@@ .* \+(\d+)/
      ADDED = /\A\+/
      REMOVED = /\A-/
      PLUSPLUS = /\A\+\+\+/

      def initialize(diff)
        @diff = diff
        @additions = compute_additions
      end

      def compute_additions
        files = Hash.new { |h, k| h[k] = [] }
        file = T.let(nil, T.nilable(String))
        line = T.let(0, Integer)
        run_start = T.let(nil, T.nilable(Integer))

        flush = -> {
          files[file] << [run_start, line - 1] if file && run_start
          run_start = nil
        }

        @diff.each_line do |l|
          case l
          when DIFF_FILE
            flush.call
            file = $1
          when HUNK_HEADER
            flush.call
            line = $1.to_i
          when PLUSPLUS
            next
          when ADDED
            run_start ||= line
            line += 1
          when REMOVED
            flush.call
          else
            flush.call
            line += 1
          end
        end

        flush.call
        files
      end

      def includes_line?(file, line)
        return false unless @additions.key?(file)

        @additions[file].any? { |start, end_line| start && line >= start && line <= end_line }
      end
    end

  end
end
