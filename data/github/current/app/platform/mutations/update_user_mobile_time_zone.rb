# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateUserMobileTimeZone < Platform::Mutations::Base
      description "Update the user's mobile time zone."

      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      argument :time_zone, String, "The user's time zone name", required: true

      error_fields
      field :user, Objects::User, "The updated user.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        user = permission.viewer
        permission.access_allowed?(
          :update_user,
          resource: user,
          current_org: nil,
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false)
      end

      def resolve(time_zone:)
        if !@context[:viewer].find_or_create_profile.update(mobile_time_zone_name: time_zone)
          raise Errors::Unprocessable.new("Time zone is invalid")
        end

        { user: @context[:viewer], errors: [] }
      end
    end
  end
end
