# typed: true
# frozen_string_literal: true

module CodeScanning
  class FileChanges
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    attr_reader :array

    sig do
      params(
        array: T::Array[T::Hash[Symbol, T.untyped]],
        from_summary: T::Boolean,
        diff_truncated: T::Boolean,
        skipped_diff_entries: T::Hash[String, Integer],
      ).void
    end
    def initialize(array, from_summary: false, diff_truncated: false, skipped_diff_entries: {})
      @array = array
      @from_summary = from_summary
      @diff_truncated = diff_truncated
      @skipped_diff_entries = skipped_diff_entries
    end

    sig { returns(T::Boolean) }
    def too_large?
      @from_summary || @diff_truncated || @skipped_diff_entries.any?
    end

    sig { returns(T::Array[String]) }
    def stats_tags
      if @skipped_diff_entries.any?
        ["diff:skipped_entry"]
      else
        []
      end
    end
  end
end
