# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProjectV2View < Platform::Mutations::Base
      docs_category :projects
      description "Deletes a view from a project."

      minimum_accepted_scopes ["project"]

      feature_flag :project_v2_view_management
      visibility :public, environments: [:dotcom, :enterprise]

      argument :view_id, ID, "The ID of the view to delete.", required: true, loads: Objects::ProjectV2View

      field :project_v2_view, Objects::ProjectV2View, "The deleted view.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, view:, **inputs)
        view.async_memex_project.then do |project|
          project.async_owner.then do |owner|
            current_org = owner if owner.organization?
            permission.access_allowed?(
              :project_v2_write,
              current_org: current_org,
              resource: project,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      def resolve(view:, **inputs)
        unless FeatureFlag.vexi.enabled?(:project_v2_view_management, context[:viewer], default: false)
          raise Errors::Unprocessable.new("ProjectV2 view management is not available.")
        end

        viewer = context[:viewer]
        if viewer.user? && viewer.should_verify_email?
          raise Errors::Unprocessable.new("Viewer must have at least one verified email.")
        end

        success = view.destroy

        unless success
          raise Errors::Unprocessable.new(view.errors.full_messages.join(", "))
        end

        { project_v2_view: view }
      end
    end
  end
end
