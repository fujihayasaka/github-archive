# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateRepositoryCustomProperty < Platform::Mutations::Base
      docs_category :repos
      include CustomPropertiesCore::Errors

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      read_arguments_from_replicas!

      description "Update a repository custom property."

      include Platform::Mutations::Shared::CustomProperties::UpdateCustomProperty

      argument :repository_custom_property_id, ID, "The global relay id of the source of the custom property.", required: true, loads: Objects::RepositoryCustomProperty, as: :custom_property
      argument :values_editable_by, Enums::RepositoryCustomPropertyValuesEditableBy, "The updated actors who can edit the values of the custom property.", required: false
      argument :require_explicit_values, Boolean, "Whether this repository custom property requires explicit values.", required: false

      field :repository_custom_property, Objects::RepositoryCustomProperty, "The updated repository custom property.", null: true

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

      def update_custom_property(source, input_fields, inputs)
        resolved_input_fields = { require_explicit_values: inputs[:custom_property].require_explicit_values, **input_fields }

        definition = Repositories.domain.custom_properties.save_definition(source, **T.unsafe(resolved_input_fields))
        { repository_custom_property: definition }
      end
    end
  end
end
