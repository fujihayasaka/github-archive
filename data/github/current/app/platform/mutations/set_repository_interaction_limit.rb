# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetRepositoryInteractionLimit < Platform::Mutations::Base
      description "Sets an interaction limit setting for a repository."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["repo"]

      argument :repository_id, ID, "The ID of the repository to set a limit for.", required: true, loads: Objects::Repository, as: :repo
      argument :limit, Enums::RepositoryInteractionLimit, "The limit to set.", required: true
      argument :expiry, Enums::RepositoryInteractionLimitExpiry, "When this limit should expire.", required: false

      field :repository, Objects::Repository, "The repository that the interaction limit was set for.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repo:, **inputs)
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:set_repository_interaction_limits,
            resource: repo, current_repo: repo, current_org: org,
            allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(repo:, **inputs)
        inputs = {
          object: repo,
          limit: inputs[:limit],
          duration: inputs[:expiry] || :one_day,
          actor: context[:viewer],
        }

        result = InteractionLimits::SetInteractionLimit.call(inputs)

        if result.success?
          { repository: result.object }
        else
          raise result.platform_error.new(result.error) # rubocop:disable GitHub/UsePlatformErrors
        end
      end
    end
  end
end
