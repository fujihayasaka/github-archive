# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ViewedFilesCount
  class Loader
    include GitHub::ResilienceMixin

    require "set"

    VIEWED_FILES_COUNT_FALLBACK = 0

    sig do
      params(
        comparison: PullRequest::Comparison,
        current_user: T.nilable(User),
        pull_request: ::PullRequest,
        paths: T.nilable(T::Array[String])
      ).returns(Numeric)
    end
    def self.load(comparison:, current_user:, pull_request:, paths: nil)
      new(comparison:, current_user:, pull_request:, paths:).load
    end

    sig do
      params(
        comparison: PullRequest::Comparison,
        current_user: T.nilable(User),
        pull_request: ::PullRequest,
        paths: T.nilable(T::Array[String])
      ).void
    end
    def initialize(comparison:, current_user:, pull_request:, paths: nil)
      @comparison = comparison
      @current_user = current_user
      @pull_request = pull_request
      @paths = paths
    end

    sig { returns(Numeric) }
    def load
      with_database_error_fallback(fallback: VIEWED_FILES_COUNT_FALLBACK) do
        if @current_user.present? || !@comparison.current?
          viewed_files = @pull_request.async_viewer_viewed_files(@current_user).sync

          # Filter viewed files by paths if paths are provided
          if @paths.present?
            paths_set = Set.new(@paths)

            viewed_files = viewed_files.select { |file| paths_set.include?(file.filepath) }
          end

          viewed_files.count
        else
          VIEWED_FILES_COUNT_FALLBACK
        end
      end
    end
  end
end
