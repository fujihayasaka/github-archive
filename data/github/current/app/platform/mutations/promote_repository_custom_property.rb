# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class PromoteRepositoryCustomProperty < Platform::Mutations::Base
      docs_category :repos
      include CustomPropertiesCore::Errors

      description "Promote a repository custom property to the enterprise level."
      minimum_accepted_scopes ["admin:enterprise"]

      read_arguments_from_replicas!

      include Platform::Mutations::Shared::CustomProperties::PromoteCustomProperty

      argument :repository_custom_property_id, ID, "The ID of the repository custom property to be promoted.", required: true, loads: Objects::RepositoryCustomProperty, as: :custom_property
      field :repository_custom_property, Objects::RepositoryCustomProperty, "The repository custom property that has been promoted.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, custom_property:, **inputs)
        source = custom_property.source
        if source.is_a?(::Organization)
          source.async_business.then do |business|
            next false unless business.present?
            permission.access_allowed?(:manage_enterprise_custom_properties_definitions, resource: business, repo: nil, organization: source, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        elsif source.is_a?(::Business)
          permission.access_allowed?(:manage_enterprise_custom_properties_definitions, resource: source, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
        else
          false
        end
      end

      def promote_custom_property(business, custom_property)
        promoted_definition = Repositories.domain.custom_properties.promote_definition(business, custom_property)
        { repository_custom_property: promoted_definition }
      end
    end
  end
end
