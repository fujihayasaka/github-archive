# typed: true
# frozen_string_literal: true

module CodeScanning
  class PullRequestAlerts
    extend T::Helpers

    class RetriableTurboscanError < StandardError
      attr_accessor :twirp_error
      attr_accessor :repo_id

      def initialize(msg, repo_id: nil, twirp_error: nil)
        super(msg)
        self.repo_id = repo_id
        self.twirp_error = twirp_error
      end
    end

    class DiffUnavailableError < StandardError
      attr_reader :stats_tags

      def initialize(message, stats_tags: [])
        super(message)
        @stats_tags = stats_tags
      end
    end

    class SummaryDiffUnavailableError < DiffUnavailableError
    end

    NotFoundError = Class.new(StandardError)
    MAX_LINE_NUMBERS = 2**32 - 1

    def self.stats_tags_for_twirp_response(response)
      if response.nil? || T.must(response).data.nil? || T.must(response).error.present?
        ["turboscan:error"].tap do |tags|
          tags << "status:#{T.must(response.error).code}" if response&.error
        end
      else
        ["turboscan:success"]
      end
    end

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

    sig { params(diff: ::GitHub::Diff, include_deletions: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.file_changes(diff, include_deletions: false)
      if diff.truncated_for_timeout? || diff.timed_out?
        summary = diff.summary

        unless summary.available?
          GitHub.logger.error("Summary diff unavailable", "gh.code_scanning.pull_request_alerts.summary_diff.unavailable_reason" => summary.unavailable_reason)
          raise SummaryDiffUnavailableError.new("Summary diff is unavailable, reason: #{summary.unavailable_reason}", stats_tags: ["summary:unavailable", "summary_unavailable:#{summary.unavailable_reason}"])
        end

        file_changes = summary.deltas.each_with_object({}) do |delta, out|
          out[delta.path] ||= { file_path: delta.path, changes: [{ added: true, start_line: 1, end_line: MAX_LINE_NUMBERS }] }
        end

        return hash_to_file_changes(file_changes)
      end

      unless diff.available?
        GitHub.logger.error("Diff unavailable", "gh.code_scanning.pull_request_alerts.diff.unavailable_reason" => diff.unavailable_reason)
        raise DiffUnavailableError, "Diff is unavailable, reason: #{diff.unavailable_reason}"
      end

      file_changes = diff.each_with_object({}) do |diff_entry, out|
        current_file = { file_path: diff_entry.path, changes: [] }

        added_lines = diff_entry.each_line.filter_map { |line| line.right if line.type == :addition }

        line_ranges(added_lines).each do |start_line, end_line|
          current_file[:changes] << { added: true, start_line:, end_line: }
        end

        if include_deletions
          deleted_lines = diff_entry.each_line.filter_map { |line| line.left if line.type == :deletion }

          line_ranges(deleted_lines).each do |start_line, end_line|
            current_file[:changes] << { added: false, start_line:, end_line: }
          end
        end

        # include whole file if no changes found
        if (diff_entry.truncated? || diff_entry.skipped?) && !diff_entry.deleted?
          current_file[:changes] << { added: true, start_line: 1, end_line: MAX_LINE_NUMBERS }
        end

        out[diff_entry.path] = current_file
      end

      # add rest of the files from deltas that were excluded from diff.entries
      diff.deltas.each do |delta|
        unless file_changes.key?(delta.path)
          file_changes[delta.path] = { file_path: delta.path, changes: [{ added: true, start_line: 1, end_line: MAX_LINE_NUMBERS }] }
        end
      end

      hash_to_file_changes(file_changes)
    end

    def self.hash_to_file_changes(hash)
      hash.each_with_object([]) do |(_, current_file), results|
        current_file[:file_path] = current_file[:file_path].dup.force_encoding("UTF-8")
        unless current_file[:file_path].valid_encoding?
          GitHub.dogstats.increment("code_scanning.pull_request_alerts.file_path.invalid_encoding")
          current_file[:file_path].scrub!
        end

        results << current_file unless current_file[:changes].empty?
      end
    end
  end
end
