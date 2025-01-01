# typed: true
# frozen_string_literal: true

module Stafftools
  module Dependabot
    class AccessReposView < Stafftools::User::ReposView

      def initialize(user:, page: 1, repo_ids:)
        super(user: user, page: page)
        @repo_ids = repo_ids.to_a
      end

      def no_repos_message
        "There are no private repositories that Dependabot has access to."
      end

      private

      # Load repositories regardless of their membership in the org. This can help troubleshoot issues
      # with token failures when we've failed to remove access after a transfer.
      def repos_of_interest
        ::Repository.where(id: @repo_ids).order(:name)
      end

    end
  end
end
