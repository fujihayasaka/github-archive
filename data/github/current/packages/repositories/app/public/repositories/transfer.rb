# typed: strict
# frozen_string_literal: true

module Repositories
  class Transfer
    extend T::Sig

    QUERY_BATCH_SIZE = 1000

    # Public: Given a list of repositories, check to see if any of the
    # repositories provided are in the middle of being transferred. This is
    # simply a batch implementation of Repository#transfer_in_progress?
    #
    # Example:
    #
    #   >> Repositories::Transfer.any_in_progress?([repo_a, repo_b])
    #   => false
    #
    # Returns a Boolean.
    sig { params(repositories: T::Array[Repository]).returns(T::Boolean) }
    def self.any_in_progress?(repositories = [])
      return false if repositories.none?

      repositories.map(&:id).each_slice(QUERY_BATCH_SIZE) do |ids|
        if RepositoryOrchestration.transfer_type.where(repository_id: ids).active.any?
          return true
        end
      end

      false
    end
  end
end
