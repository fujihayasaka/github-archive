# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class InternalReposView < ReposView
      def no_repos_message
        "This user has no internal repositories."
      end

      def span_symbol(repo)
        if pinned_repositories.include?(repo)
          "pin"
        else
          super
        end
      end

      private

      def repos_of_interest
        repos = user.internal_repositories

        if pinned_repositories.size > 0
          repos = repos.sort { |a, b| sorter(a, b) }
        else
          repos = repos.order(:name)
        end
        repos
      end

      def pinned_repositories
        @pinned_repositories ||= user.pinned_repositories
      end

      # Private: If the two given repositories are both pinned to the user's profile,
      # they will be sorted according to their `position` in the "Pinned" list.
      # Pinned items are sorted before items that are not pinned. When neither item is
      # pinned, they are sorted by their name, case insensitive.
      def sorter(repo1, repo2)
        pinned_repo_index1 = pinned_repositories.index(repo1)
        pinned_repo_index2 = pinned_repositories.index(repo2)

        if pinned_repo_index1 && pinned_repo_index2
          pinned_repo_index1 <=> pinned_repo_index2
        elsif pinned_repo_index1
          -1
        elsif pinned_repo_index2
          1
        else
          repo1.name.downcase <=> repo2.name.downcase
        end
      end
    end
  end
end
