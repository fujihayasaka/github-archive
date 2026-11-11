# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::Comments::Filters
  class DiffFilterConfig < BaseFilter
    EXCLUDE_PATTERNS = T.let(
      Array(PullRequests::Copilot::DiffsFilter::CONFIG.dig("globs", "exclude")).freeze,
      T::Array[String]
    )

    sig { override.returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def filter!
      comments.reject! do |comment|
        EXCLUDE_PATTERNS.any? do |pattern|
          File.fnmatch(pattern, comment.with_indifferent_access["path"], File::FNM_PATHNAME)
        end
      end

      comments
    end
  end
end
