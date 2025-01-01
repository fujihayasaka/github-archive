# typed: true
# frozen_string_literal: true

module Repositories
  class ForkButtonContentComponent < ApplicationComponent
    include RepositoryAnalyticsHelper # for data attributes

    # repository - The repository to be forked
    def initialize(repository:, can_fork:)
      @repository = repository

      # this is a visual change only, so it's fine to pass in from the other request. the actual logic is checked
      # on the create fork page.
      @can_fork = can_fork
    end

    private

    attr_reader :repository, :can_fork

    # Public: Returns existing forks of personal account and organizations
    memoize def all_existing_forks
      return [] if !logged_in?
      forks = repository.network.repositories.where(owner: current_user.organization_ids)
      forks = forks - [repository]
      forks.unshift(existing_user_fork) if repository.owner_id != current_user.id && existing_user_fork
      forks
    end

    # Public: Returns the user's personal fork of the repository, or nil.
    memoize def existing_user_fork
      current_user&.my_fork_of(repository)
    end
  end
end
