# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EarlyAccessMembership < Platform::Objects::Base
      description "A submitted user request for an account to join an early access program"

      visibility :internal
      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      minimum_accepted_scopes ["site_admin"]
      global_id_field :id, description: "The Node ID of the EarlyAccessMembership object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      created_at_field
      updated_at_field

      field :account, Unions::Account, description: "The user, organization, or enterprise account to grant early access to", method: :async_member, null: true
      field :actor, Objects::User, description: "The user that submitted the early access request", method: :async_actor, null: true
      field :feature, Enums::EarlyAccessMembershipFeature, description: "The feature that this request is for", method: :feature_slug, null: false
      field :is_approved, Boolean, description: "Indicates if this request is approved and access to the feature has been granted", method: :feature_enabled?, null: false
    end
  end
end
