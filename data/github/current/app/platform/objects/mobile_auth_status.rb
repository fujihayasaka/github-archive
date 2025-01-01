# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileAuthStatus < Platform::Objects::Base
      description "Represents the status of the mobile device auth for the user."

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

      # This object is marked as mobile_only and is currently only accessible via an already authorized User
      # object. We are just being extra careful here to ensure that the viewer is the user in question.
      def self.async_viewer_can_see?(permission, object)
        permission.viewer&.id == object[:user_id]
      end

      field :has_valid_device_auth_key, Boolean, "Whether the requestor has a valid device key. The requestor can use this to determine ahead of time that approving or rejecting the returned auth request will fail.", null: false
      field :active_auth_request, MobileAuthRequest, "The active auth request for the user, if any.", null: true
    end
  end
end
