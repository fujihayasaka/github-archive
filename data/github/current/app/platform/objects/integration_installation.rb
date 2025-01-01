# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IntegrationInstallation < Platform::Objects::Base
      description "The installation of a GitHub App on a target account"
      visibility :internal


      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        if permission.authenticating_as_app?
          true
        else
          object.async_target.then do |target|
            # See if the target account should be hidden for being spammy
            !target.hide_from_user?(permission.viewer)
          end
        end
      end

      minimum_accepted_scopes ["repo"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      implements Interfaces::FeatureFlaggable

      global_id_field :id, description: "The Node ID of the IntegrationInstallation object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :target, Unions::Account, description: "The target user or org account for this installation.", null: false
      field :app, App, description: "The installed GitHub app.", null: false, method: :async_integration

      field :configuration_url, Scalars::URI, description: "The HTTP URL for the installation configuration", null: false

      def configuration_url
        @object.async_configuration_url(@context[:viewer])
      end
    end
  end
end
