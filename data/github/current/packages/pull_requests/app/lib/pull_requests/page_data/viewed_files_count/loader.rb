# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ViewedFilesCount
  class Loader
    include GitHub::ResilienceMixin

    VIEWED_FILES_COUNT_FALLBACK = 0

    sig do
      params(
        comparison: PullRequest::Comparison,
        current_user: T.nilable(User),
        pull_request: ::PullRequest,
      ).returns(Numeric)
    end
    def self.load(comparison:, current_user:, pull_request:)
      new(comparison:, current_user:, pull_request:).load
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        current_user: T.nilable(User),
        pull_request: ::PullRequest,
      ).void
    end
    def initialize(comparison:, current_user:, pull_request:)
      @comparison = comparison
      @current_user = current_user
      @pull_request = pull_request
    end

    sig { returns(Numeric) }
    def load
      with_database_error_fallback(fallback: VIEWED_FILES_COUNT_FALLBACK) do
        if @current_user.present? || !@comparison.current?
          @pull_request.async_viewer_viewed_files(@current_user).sync.count
        else
          VIEWED_FILES_COUNT_FALLBACK
        end
      end
    end
  end
end
