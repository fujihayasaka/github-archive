# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateRepositoryCustomProperty < Platform::Mutations::Base
      include CustomPropertiesCore::Errors

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      read_arguments_from_replicas!

      description "Update a repository custom property."

      # value_type and property_name cannot be updated once created
      argument :repository_custom_property_id, ID, "The global relay id of the source of the custom property.", required: true, loads: Objects::RepositoryCustomProperty, as: :repository_custom_property
      argument :description, GraphQL::Types::String, "The updated description of the custom property.", required: false
      argument :allowed_values, [GraphQL::Types::String], "The updated allowed values for the custom property.", required: false
      argument :required, GraphQL::Types::Boolean, "Whether the updated custom property is required.", required: false
      argument :default_value, GraphQL::Types::String, "The updated default value for the custom property if the property is required.", required: false
      argument :values_editable_by, Enums::RepositoryCustomPropertyValuesEditableBy, "The updated actors who can edit the values of the custom property.", required: false
      argument :regex, GraphQL::Types::String, "The regex pattern that the value of the custom property must match, if the `value_type` is `string`.", required: false

      field :repository_custom_property, Objects::RepositoryCustomProperty, "The updated repository custom property.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository_custom_property:, **inputs)
        source = repository_custom_property.source
        if source.is_a?(::Organization)
          permission.access_allowed?(:manage_org_custom_properties_definitions, resource: source, current_repo: nil, current_org: source, allow_integrations: true, allow_user_via_granular_actor: true)
        elsif source.is_a?(::Business)
          permission.access_allowed?(:manage_enterprise_custom_properties_definitions, resource: source, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
        else
          false
        end
      end

      def resolve(repository_custom_property:, **inputs)
        begin
          existing_input_fields = {
            property_name: repository_custom_property.property_name,
            value_type: repository_custom_property.value_type,
            required: repository_custom_property.required,
            default_value: repository_custom_property.default_value,
            description: repository_custom_property.description,
            allowed_values: repository_custom_property.allowed_values,
            values_editable_by: repository_custom_property.values_editable_by
          }

          resolved_input_fields = { **existing_input_fields, **inputs }
          source = repository_custom_property.source

          definition = Repositories.domain.custom_properties.save_definition(source, **T.unsafe(resolved_input_fields))
          { repository_custom_property: definition }
        rescue InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
          raise Errors::Unprocessable.new(exception.message)
        end
      end
    end
  end
end
