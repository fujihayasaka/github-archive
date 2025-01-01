# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    # Jump to organizations or repositories that you're a member of or have contribute to
    class JumpToMembersOnlyPrefetchedProvider < PrefetchedProvider
      def self.modes
        [
          :global_jump_to,
          :owner_jump_to,
          :modeless_global,
          :modeless_owner
        ]
      end

      def search(_)
        objects = search_for_owners
        objects += search_for_repositories
        objects.uniq.map do |object|
          Result.jump_to(object, context: context)
        end
      end

      def search_for_owners
        return [] if scope.owner

        [current_user] + current_user.organizations.limit(1000).to_a
      end

      # Get repositories with commits from current user and order from most to least contributions.
      # Optionally, Provide a list of repository IDs to limit the results.
      def repos_with_contributions(repository_ids = nil, limit: 100, include_repositories_without_contributions: false)
        sorted_repository_ids = CommitContributions.domain.top_contributed_repository_ids(user: current_user, limit: limit, repository_ids: repository_ids)

        repositories = Repositories::Public.load_repositories(sorted_repository_ids)
        repositories = repositories.sort_by { |repo| T.must(sorted_repository_ids.index(repo.id)) }

        if repository_ids && include_repositories_without_contributions
          repositories_without_contributions = Repository.where(id: repository_ids - repositories.map(&:id))
          repositories += repositories_without_contributions
        end

        repositories
      end

      def search_for_repositories
        repositories =
          if scope.organization?
            # The collection of all org repo IDs might be huge (eg. >300K) which can result in a huge IN (...)
            # clause when querying for commit contributions. The collection of all repos the current_user has
            # committed to in the past year should be much smaller, so start with that list and use it to pass
            # along the relevant subset of org repos, which should always query with a much smaller IN (...) clause.
            cutoff = 1.year.ago
            candidate_repo_ids = CommitContributions.domain.contributed_repo_ids(user: current_user, since: cutoff)
            repos_with_contributions(scope.organization.repositories.where(id: candidate_repo_ids).pluck(:id), limit: 1000)
          elsif scope.object == current_user
            repos_with_contributions(current_user.repositories.pluck(:id), limit: 1000, include_repositories_without_contributions: true)
          elsif scope.user?
            repos_with_contributions(scope.user.repositories.pluck(:id))
          elsif scope.blank?
            repos_with_contributions
          else
            []
          end

        repo_visibility = Promise.all(repositories.map { |r| r&.async_readable_by?(current_user) }).sync
        repositories.select.with_index { |_, i| repo_visibility[i] }
      end
    end
  end
end
