# typed: true
# frozen_string_literal: true

module CodeScanning
  class DiffStatus
    sig { returns(GitHub::Diff) }
    attr_reader :diff

    sig { params(diff: GitHub::Diff).void }
    def initialize(diff)
      @diff = diff
    end

    sig { returns(T.nilable(String)) }
    def unavailable_reason
      return if diff.available?

      case
      when diff.timed_out?
        "timeout"
      when diff.too_busy?
        "too busy"
      when diff.corrupt?
        "corrupt"
      when diff.missing_commits?
        "missing commits"
      else
        "unknown reason"
      end
    end

    sig { returns(T.nilable(String)) }
    def truncated_reason
      return unless diff.truncated?

      case
      when diff.truncated_for_max_files?
        "max files"
      when diff.truncated_for_max_lines?
        "max lines"
      when diff.truncated_for_max_size?
        "max size"
      when diff.truncated_for_timeout?
        "timeout"
      else
        "unknown reason"
      end
    end

    def stats_tags
      if !diff.available?
        ["diff:unavailable", "diff_unavailable:#{unavailable_reason&.tr(' ', '-')}"]
      elsif diff.truncated?
        ["diff:truncated", "diff_truncated:#{truncated_reason&.tr(' ', '-')}"]
      else
        # Assuming available and not truncated means we got the full diff
        ["diff:success"]
      end
    end
  end
end
