# typed: true
# frozen_string_literal: true

module CodeScanning
  class PullRequestAlertSummaryGenerator
    extend T::Helpers

    sig { params(changed_lines: T::Array[Integer]).returns(T::Array[[Integer, Integer]]) }
    def self.line_ranges(changed_lines)
      # compact runs of consecutive lines numbers
      changed_lines.sort.inject([]) do |out, line|
        # update the latest range end position if this is the next line in the range
        if out.count > 0 && line == out.last[1] + 1
          out.last[1] = line
          next out
        end
        out.push [line, line]
      end
    end

    sig { params(diffs: ::GitHub::Diff, include_deletions: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.changed_lines(diffs, include_deletions: false)
      diffs.filter_map do |change|
        current_file = { file_path: change.path, changes: [] }

        begin
          changed_lines = change.each_line.filter { |line| line.type == :addition }.map(&:right)

          line_ranges(changed_lines).each do |start_line, end_line|
            current_file[:changes] << { added: true, start_line:, end_line: }
          end
        end

        if include_deletions
          changed_lines = change.each_line.filter { |line| line.type == :deletion }.map(&:left)

          line_ranges(changed_lines).each do |start_line, end_line|
            current_file[:changes] << { added: false, start_line:, end_line: }
          end
        end

        # If there are no relevant changes then we don't need to process this file
        next if current_file[:changes].empty?

        current_file
      end
    end
  end
end
