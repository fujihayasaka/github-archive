# typed: true
# frozen_string_literal: true

module ConditionalAccess
  module Helpers
    module OutsideCollaboratorChecks
      BATCH_SIZE = 1_000

      # Internal: Determine if the actor is an outside collaborator on the
      # organization.
      #
      # Returns a Boolean.
      def actor_outside_collaborator_for_org?(organization)
        T.bind(self, T.any(
          ::ConditionalAccess::Policy::LegacyPersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokens::AppliedIn
        ))

        direct_repository_ids = Authorization::Service.new.subject_ids(actor: actor, subject_type: "Repository")

        return false if direct_repository_ids.empty?

        direct_repository_ids.in_groups_of(BATCH_SIZE).any? do |repo_ids|
          Repositories::Public.filter_repo_ids_to_org(
            repo_ids: repo_ids, organization_id: organization.id
          ).limit(1).exists?
        end
      end

      # Internal: Determine if the actor is an outside collaborator on the
      # organization using checking resource.
      #
      # Returns a Boolean.
      def actor_outside_collaborator_for_resource?(organization, resource)
        T.bind(self, T.any(
          ::ConditionalAccess::Policy::LegacyPersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokens::AppliedIn
        ))

        repo = (resource if Repositories::Public.unsafe_is_repository?(resource)) || self.try(:repository)
        return false unless repo

        organization.user_collaborates_on_any_repositories?(actor.id, [repo.id])
      end
    end
  end
end
