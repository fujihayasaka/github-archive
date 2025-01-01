# typed: true
# frozen_string_literal: true

module CodeScanning
  class PullRequestAlertsDiff
    attr_reader :pull_request

    PAGE_SIZE = 50

    def initialize(pull_request, max_changes: 75_000)
      @pull_request = pull_request
      @max_changes = max_changes
    end

    attr_reader :file_changes
    attr_reader :unavailable_reason, :unavailable_reason_symbol
    attr_reader :truncated_reason, :truncated_reason_symbol
    attr_reader :capped
    alias_method :capped?, :capped

    def detect_changes!
      @file_changes = []
      @unavailable_reason = @unavailable_reason_symbol = nil
      @truncated_reason = @truncated_reason_symbol = nil
      @capped = false

      delta_index_from = 0
      change_count = 0

      delta_diff = pull_request.historical_comparison.init_diffs

      loop do
        delta_index_range = delta_index_from..(delta_index_from + PAGE_SIZE - 1)
        delta_diff = delta_diff.only_params # This is needed to create a fresh clone of the diff
        delta_diff.add_delta_indexes(delta_index_range.to_a)

        if !delta_diff.available? || delta_diff.truncated?
          register_unavailable_reason!(delta_diff)
          register_truncated_reason!(delta_diff)
          break
        end

        delta_files = delta_diff.to_a
        break if delta_files.empty?

        delta_files.each do |diff|
          current_file = { file_path: diff.path, changes: [] }

          addition_lines = diff.each_line.filter { |line| line.type == :addition }
          # If there are no additions then we don't need to process this file
          if addition_lines.length == 0
            next
          end

          start_line = addition_lines[0].right
          end_line = addition_lines[0].right
          addition_lines.each_cons(2) do |prev_line, line|
            if line.right == prev_line.right + 1
              end_line = line.right
            else
              current_file[:changes] << { added: true, start_line: start_line, end_line: end_line }
              start_line = line.right
              end_line = line.right
            end
          end
          # "Commit" the last block
          current_file[:changes] << { added: true, start_line: start_line, end_line: end_line }

          if change_count + current_file[:changes].size > max_changes
            @capped = true
            break
          end

          change_count += current_file[:changes].size
          @file_changes << current_file
        end

        delta_index_from = delta_index_range.max + 1
      end

      nil # Return value should not be used, instead read from the attr readers.
    end

    private

    attr_reader :max_changes

    def register_unavailable_reason!(diff)
      @unavailable_reason = diff.unavailable_reason

      @unavailable_reason_symbol =
        case
        when diff.timed_out?
          :timeout
        when diff.too_busy?
          :too_busy
        when diff.corrupt?
          :corrupt
        when diff.missing_commits?
          :missing_commits
        else
          :other
        end
    end

    def register_truncated_reason!(diff)
      @truncated_reason = diff.truncated_reason

      @truncated_reason_symbol =
        case
        when diff.truncated_for_max_files?
          :truncated_for_max_files
        when diff.truncated_for_max_lines?
          :truncated_for_max_lines
        when diff.truncated_for_max_size?
          :truncated_for_max_size
        when diff.truncated_for_timeout?
          :truncated_for_timeout
        else
          :other
        end
    end
  end
end
