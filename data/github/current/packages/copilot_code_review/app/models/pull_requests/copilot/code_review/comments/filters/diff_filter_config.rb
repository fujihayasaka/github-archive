# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::Comments::Filters
  class DiffFilterConfig < BaseFilter
    EXCLUDE_PATTERNS = T.let(
      Array(PullRequests::Copilot::DiffsFilter::CONFIG.dig("globs", "exclude")).freeze,
      T::Array[String]
    )

    DIRECTORY_EXCLUDE_PATTERNS = T.let(
      Array(PullRequests::Copilot::DiffsFilter::CONFIG.dig("globs", "directory_exclude")).freeze,
      T::Array[String]
    )

    sig { override.returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def filter!
      comments.reject! do |comment|
        path = comment.with_indifferent_access["path"]
        excluded_by_pattern = EXCLUDE_PATTERNS.any? { |pattern| File.fnmatch(pattern, path, File::FNM_PATHNAME) }
        excluded_by_directory = DIRECTORY_EXCLUDE_PATTERNS.any? { |pattern| File.fnmatch(pattern, path, File::FNM_PATHNAME) }

        excluded_by_pattern || (excluded_by_directory && !path.end_with?(".rs"))
      end

      comments
    end
  end
end
