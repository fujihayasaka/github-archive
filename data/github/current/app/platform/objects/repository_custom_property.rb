# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryCustomProperty < Platform::Objects::Base
      model_name "CustomPropertyDefinition"
      description "A repository custom property."

      minimum_accepted_scopes ["read:org", "read:enterprise"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, property_definition)
        property_definition.source.then do |source|
          if source.is_a?(::Organization)
            has_org_permission = permission.access_allowed?(:read_org_custom_properties, resource: source, current_repo: nil, current_org: source, allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false)
            next true if has_org_permission

            source.async_business.then do |business|
              next false unless business.present?
              permission.access_allowed?(:read_enterprise_custom_properties, resource: business, repo: nil, organization: source, allow_integrations: true, allow_user_via_granular_actor: true)
            end
          elsif source.is_a?(::Business)
            permission.access_allowed?(:read_enterprise_custom_properties, resource: source, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          else
            false
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, property_definition)
        property_definition.source.then do |source|
          if source.is_a?(::Organization)
            permission.typed_can_see?("Organization", source)
          elsif source.is_a?(::Business)
            permission.typed_can_see?("Enterprise", source)
          else
            false
          end
        end
      end

      implements_node templates: [[:rcp, :source_type, :source_id, :id]], as: "RCP", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |definition|
        { prefix: :rcp, source_type: definition.source_type, source_id: definition.source_id, id: definition.id }
      end

      include Platform::Helpers::CustomPropertyBase

      field :values_editable_by, Enums::RepositoryCustomPropertyValuesEditableBy, description: "Who can edit the values of this repository custom property.", null: false
      field :require_explicit_values, Boolean, description: "Whether this repository custom property requires explicit values.", null: true
    end
  end
end
