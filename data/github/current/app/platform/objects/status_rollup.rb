# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StatusRollup < Platform::Objects::Base
      include StatusHelper

      description "A status rollup."

      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_access?("Repository", object.repository)
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        repo = object.repository
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

      def self.load_from_status_checks(repository, status_checks, workflows_pending_approval)
        Platform::Models::StatusRollup.new(repository: repository, status_checks: status_checks, workflows_pending_approval: workflows_pending_approval)
      end

      field :summary, [Objects::CheckStateRollup], null: false, description: "A list of check state rollups."

      def summary
        @object.status_checks
          .group_by { |status| StatusCheckConfig.enum_state(status.state) }
          .map { |state, statuses| { repository: @object.repository, count: statuses.length, state: state } }
      end

      field :combined_state, Platform::Enums::StatusRollupCombinedState, null: false, description: "The combined state of the status rollup."
      def combined_state
        calculate_combined_state(@object.status_checks, @object.workflows_pending_approval)
      end
    end
  end
end
