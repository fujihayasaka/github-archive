# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateProjectV2View < Platform::Mutations::Base
      docs_category :projects
      description "Creates a new view in a project."

      minimum_accepted_scopes ["project"]

      feature_flag :project_v2_view_management
      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the project to create a view in.", required: true, loads: Objects::ProjectV2
      argument :name, String, "The name of the view.", required: true
      argument :layout, Enums::ProjectV2ViewLayout, "The layout of the view.", required: true

      field :project_v2_view, Objects::ProjectV2View, "The new view.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project:, **inputs)
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

      def resolve(project:, name:, layout:, **inputs)
        unless FeatureFlag.vexi.enabled?(:project_v2_view_management, context[:viewer], default: false)
          raise Errors::Unprocessable.new("ProjectV2 view management is not available.")
        end

        viewer = context[:viewer]
        if viewer.user? && viewer.should_verify_email?
          raise Errors::Unprocessable.new("Viewer must have at least one verified email.")
        end

        if project.closed?
          raise Errors::Unprocessable.new("Cannot create a view for a closed project.")
        end

        layout_enum = layout.underscore.to_sym

        view = project.memex_project_views.build(
          creator: viewer,
          name: name,
          layout: layout_enum,
        )

        if view.valid?
          project.save_view_with_priority!(view, **{ position: :top })
        end

        unless view.persisted?
          raise Errors::Unprocessable.new(view.errors.full_messages.join(", "))
        end

        { project_v2_view: view }
      end
    end
  end
end
