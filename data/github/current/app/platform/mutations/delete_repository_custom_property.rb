# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteRepositoryCustomProperty < Platform::Mutations::Base
      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      read_arguments_from_replicas!

      description "Delete a repository custom property."

      argument :id, ID, "The global relay id of the custom property to be deleted.", required: true, loads: Objects::RepositoryCustomProperty, as: :custom_property

      field :repository_custom_property, Objects::RepositoryCustomProperty, "The deleted custom property.", null: true
      include Platform::Mutations::Shared::CustomProperties::DeleteCustomProperty

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, custom_property:, **inputs)
        source = custom_property.source
        if source.is_a?(::Organization)
          permission.access_allowed?(:manage_org_custom_properties_definitions, resource: source, current_repo: nil, current_org: source, allow_integrations: true, allow_user_via_granular_actor: true)
        elsif source.is_a?(::Business)
          permission.access_allowed?(:manage_enterprise_custom_properties_definitions, resource: source, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
        else
          false
        end
      end

      def delete_custom_property(custom_property)
        Repositories.domain.custom_properties.delete_definition(custom_property.source, custom_property.property_name)
        { repository_custom_property: custom_property }
      end
    end
  end
end
