# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    # Jump to organizations or repositories that you contribute to (this uses ElasticSearch)
    class JumpToMembersOnlyProvider < JumpToProvider
      def self.modes
        [
          :global_jump_to,
          :owner_jump_to,
          :modeless_global,
          :modeless_owner
        ]
      end

      def search_for_owners(_)
        super.select do |owner|
          relevant?(owner)
        end
      end

      def search_for_repositories(query)
        # Get results via the ES query in JumpToProvider, to filter out repos to show to current user.
        repositories = super(query)

        # First, check if the current user is a member of the repositories.
        repo_memberships = Promise.all(repositories.map { |r| r&.async_member?(current_user) }).sync
        member_repo_ids = repositories.filter_map.with_index { |r, i| r.id if repo_memberships[i] }

        # For all non-member repositories, check if the current user is a contributor.
        non_member_repositories = repositories.reject { |r| member_repo_ids.include?(r.id) }
        repo_contributors = Promise.all(non_member_repositories.map { |r| r&.async_contributor?(current_user) }).sync
        contributor_repo_ids = non_member_repositories.filter_map.with_index { |r, i| r.id if repo_contributors[i] }

        # For the remaining (non-member, non-contributor) repositories, check whether the current user owns
        # or belongs to the org that owns the repo.
        remaining_repositories = repositories.reject { |r| (member_repo_ids + contributor_repo_ids).include?(r.id) }
        remaining_repo_owner_ids = remaining_repositories.map(&:owner_id).uniq
        org_repo_owners = Organization.where(id: remaining_repo_owner_ids)
        org_memberships = Promise.all(org_repo_owners.map { |o| o.async_member?(current_user) }).sync
        relevant_owner_ids = org_repo_owners.filter_map.with_index { |o, i| o.id if org_memberships[i] }
        relevant_owner_ids << current_user.id if current_user
        relevant_repo_ids = remaining_repositories.filter_map { |r| r.id if relevant_owner_ids.include?(r.owner_id) }

        jump_to_repository_ids = member_repo_ids + contributor_repo_ids + relevant_repo_ids

        repositories.select do |repository|
          jump_to_repository_ids.include?(repository.id)
        end
      end

      # Check if owner is relevant to current_user.
      def relevant?(owner)
        if owner.user?
          owner == current_user
        elsif owner.organization?
          owner.direct_or_team_member?(current_user)
        end
      end
    end
  end
end
