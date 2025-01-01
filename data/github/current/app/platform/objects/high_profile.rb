# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class HighProfile < Platform::Objects::Base
      description "Represents the high profile status for a User, Org, or Repository"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.viewer.site_admin?
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :is_high_profile, Boolean, "If the user, org, or repository meets Trust & Safety high profile criteria", null: true
      field :reason, String, description: "The reason why the user, org, or repository met Trust & Safety high profile criteria", null: false
    end
  end
end
