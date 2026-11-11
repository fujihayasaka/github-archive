# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetRepositoryCustomPropertyValues < Platform::Mutations::Base
      include Platform::Mutations::Shared::SetCustomPropertyValues

      minimum_accepted_scopes ["repo", "admin:org"]

      read_arguments_from_replicas!

      description "Set repository custom property values for a repository."

      argument :repository_id, ID, "The ID of the repository to set properties for.", required: true, loads: Objects::Repository
      field :repository, Objects::Repository, "The repository that the custom properties were set for.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |owner|
          next false unless owner

          repo_permission = permission.access_allowed?(:edit_repo_custom_properties_values, resource: repository, current_repo: repository, current_org: owner, allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false)
          next true if repo_permission

          permission.access_allowed?(:edit_org_custom_properties_values, resource: owner, current_repo: repository, current_org: owner, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      private

      def set_values_for(inputs, properties)
        repository = inputs[:repository]
        Repositories.domain.custom_properties.set_properties_for(repository.owner, [repository], properties, actor: context[:viewer])

        { repository: repository }
      end
    end
  end
end
