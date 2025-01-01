# typed: strict
# frozen_string_literal: true

module Restorables
  # Public: A data object that holds the counts of different types of data
  # associated with a repository visibility change.
  class VisibilityChangedRepositoryCounts
    sig { returns(Integer) }
    attr_reader :repository_stars_count

    sig { returns(Integer) }
    attr_reader :watched_repositories_count

    sig { returns(Integer) }
    attr_reader :custom_watched_repositories_count

    sig { returns(Integer) }
    attr_reader :watched_repository_threads_count

    sig do
      params(
        repository_stars_count: Integer,
        watched_repositories_count: Integer,
        custom_watched_repositories_count: Integer,
        watched_repository_threads_count: Integer
      ).void
    end
    def initialize(
      repository_stars_count: 0,
      watched_repositories_count: 0,
      custom_watched_repositories_count: 0,
      watched_repository_threads_count: 0
    )
      @repository_stars_count = repository_stars_count
      @watched_repositories_count = watched_repositories_count
      @custom_watched_repositories_count = custom_watched_repositories_count
      @watched_repository_threads_count = watched_repository_threads_count
    end

    sig { returns(T::Boolean) }
    def empty?
      repository_stars_count.zero? &&
        watched_repositories_count.zero? &&
        custom_watched_repositories_count.zero? &&
        watched_repository_threads_count.zero?
    end
  end
end
