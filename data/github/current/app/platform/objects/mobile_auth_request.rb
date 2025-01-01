# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileAuthRequest < Platform::Objects::Base
      description "Represents an active auth request for user."

      mobile_only true
      minimum_accepted_scopes ["user"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # MobileAuthRequest is only accessible on the MobileAuthStatus object,
      # which has already validated viewer_can_see permissions
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :id, Integer, "The ID associated with the mobile auth request.", null: false
      field :payload, String, "The random payload (base64 encoded) provided to the mobile device to be signed for mobile device auth.", null: false
      field :challenge_required, Boolean, "Whether the auth request requires a user input challenge in order to approve.", null: false
      field :type, Enums::MobileAuthRequestType, "The type of the mobile auth request.", null: false
    end
  end
end
