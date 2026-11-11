# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetRepositoryCustomPropertyValues < Platform::Mutations::Base
      minimum_accepted_scopes ["repo", "admin:org"]

      read_arguments_from_replicas!

      description "Set repository custom property values for a repository."

      include Platform::Mutations::Shared::CustomProperties::SetCustomPropertyValues

      argument :repository_id, ID, "The ID of the repository to set properties for.", required: true, loads: Objects::Repository, as: :target
      field :repository, Objects::Repository, "The repository that the custom properties were set for.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, target:, **inputs)
        permission.async_owner_if_org(target).then do |owner|
          next false unless owner

          repo_permission = permission.access_allowed?(:edit_repo_custom_properties_values, resource: target, current_repo: target, current_org: owner, allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false)
          next true if repo_permission

          permission.access_allowed?(:edit_org_custom_properties_values, resource: owner, current_repo: target, current_org: owner, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      private

      def set_values_for(target, properties)
        Repositories.domain.custom_properties.set_properties_for(target.owner, [target], properties, actor: context[:viewer])
        { repository: target }
      end
    end
  end
end
