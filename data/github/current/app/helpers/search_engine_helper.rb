# typed: strict
# frozen_string_literal: true

module SearchEngineHelper
  sig { params(repository: Repository).returns(T::Boolean) }
  def hide_repository_from_search_engines?(repository)
    return true if repository.route.nil? || repository.empty? # empty
    return true if repository.spammy?
    return true if repository.noindex?

    if repository.fork?
      # If this is a fork with a different name than its root,
      # include it in Google results. Probably a new network.
      return false if repository.name != repository.root.name
      return true if !repository.popular_fork?
    end

    false # let Google see it
  end
end
