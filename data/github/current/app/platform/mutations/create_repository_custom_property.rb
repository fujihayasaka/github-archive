# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateRepositoryCustomProperty < Platform::Mutations::Base
      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      read_arguments_from_replicas!

      description "Create a repository custom property."

      argument :values_editable_by, Enums::RepositoryCustomPropertyValuesEditableBy, "The allowed actors who can edit the values of a custom property.", required: false

      field :repository_custom_property, Objects::RepositoryCustomProperty, "The newly created repository custom property.", null: true
      include Platform::Mutations::Shared::ICustomProperty
      include Platform::Mutations::Shared::CreateCustomProperty

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, source:, **inputs)
        if source.is_a?(::Organization)
          permission.access_allowed?(:manage_org_custom_properties_definitions, resource: source, current_repo: nil, current_org: source, allow_integrations: true, allow_user_via_granular_actor: true)
        elsif source.is_a?(::Business)
          permission.access_allowed?(:manage_enterprise_custom_properties_definitions, resource: source, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
        else
          false
        end
      end

      private

      def domain
        Repositories.domain.custom_properties
      end

      def transform_result(result)
        {
          repository_custom_property: result,
        }
      end
    end
  end
end
