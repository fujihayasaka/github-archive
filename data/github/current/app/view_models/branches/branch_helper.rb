# typed: false
# frozen_string_literal: true

module Branches
  module BranchHelper
    # Public: The limit of branches that the BranchFinder
    # should request.
    #
    # Override this method to set a different limit.
    #
    # Returns an Integer.
    def branch_limit
      5
    end

    # Public: Set the options for the BranchFinder.
    #
    # Options:
    #
    # limit - Limit on how many branches to fetch
    # page  - Optional page of branch results
    # query - Optional search query
    #
    # Returns a Hash.
    def branch_finder_options
      {
        limit: branch_limit,
      }
    end

    # Public: A memoized instances of the BranchFinder
    # for the current repository.
    #
    # Returns a Branches::BranchFinder object.
    def branch_finder
      @branch_finder ||= ::Branches::BranchFinder.new(
        repository,
        current_user,
        **branch_finder_options,
      )
    end
  end
end
