# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CheckStateRollup < Platform::Objects::Base
      description "A status check rollup."

      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_access?("Repository", object[:repository])
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        repo = object[:repository]
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(
            :get_status_check_rollup,
            resource: repo,
            current_org: org,
            current_repo: repo,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      field :count, Integer, null: false, description: "The number of status checks in this rollup."
      field :state, Platform::Enums::StatusCheckState, null: false, description: "The status check state for this rollup."
    end
  end
end
