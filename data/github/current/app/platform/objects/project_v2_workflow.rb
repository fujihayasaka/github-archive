# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2Workflow < Objects::Base

      model_name "MemexProjectWorkflow"

      description "A workflow inside a project."

      visibility :public, environments: [:dotcom, :enterprise]

      minimum_accepted_scopes ["read:project"]

      PREFIX = Helpers::ProjectV2::Prefix.new("PWF", :opwf, :upwf)
      implements_node templates: [
        [PREFIX.org, :owner_id, :project_id, :id],
        [PREFIX.user, :owner_id, :project_id, :id]
      ],
      as: PREFIX.to_s,
      ready_date: "1970-01-01" do |workflow|
        workflow.async_memex_project.then do |project|
          project.async_owner.then do |owner|
            {
              prefix: owner.organization? ? PREFIX.org : PREFIX.user,
              owner_id: owner.id,
              project_id: project.id,
              id: workflow.id
            }
          end
        end
      end


      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.async_memex_project.then do |project|
          project.async_owner.then do |owner|
            current_org = owner if owner.organization?

            permission.access_allowed?(
              :project_v2_writer_read_only,
              current_org: current_org,
              resource: project,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.async_memex_project.then do |project|
          project.deleted_at.nil? && project.viewer_can_write?(permission.viewer)
        end
      end

      database_id_field

      created_at_field

      updated_at_field

      field :number, Integer, "The number of the workflow.", null: false
      field :name, String, "The name of the workflow.", null: false
      field :enabled, Boolean, "Whether the workflow is enabled.", null: false

      field :project, Platform::Objects::ProjectV2, description: "The project that contains this workflow.", null: false, method: :async_memex_project
    end
  end
end
