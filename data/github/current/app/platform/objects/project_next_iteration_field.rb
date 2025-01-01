# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextIterationField < Platform::Objects::Base
      implements Platform::Interfaces::ProjectNextFieldCommon
      description "An iteration field inside a project."

      mobile_only true

      implements_node templates: [
          [:opnif, :org_id, :project_next_id, :project_next_iteration_field_id],
          [:upnif, :user_id, :project_next_id, :project_next_iteration_field_id]
        ],
        as: "PNIF",
        ready_date: Platform::Interfaces::ProjectNextFieldCommon::PROJECT_NEXT_COHORT,
        uses_database_id: false do |project_next_field|
        project_next_field.async_memex_project.then do |project_next|
          case project_next.owner_type
          when "Organization"
            {
              prefix: :opnif,
              org_id: project_next.owner_id,
              project_next_id: project_next.id,
              project_next_iteration_field_id: project_next_field.id
            }
          when "User"
            {
              prefix: :upnif,
              user_id: project_next.owner_id,
              project_next_id: project_next.id,
              project_next_iteration_field_id: project_next_field.id
            }
          else
            raise Platform::Errors::Internal, "Unexpected project owner: #{project_next.owner_type.inspect}"
          end
        end
      end

      minimum_accepted_scopes ["read:org"]

      def self.async_api_can_access?(permission, project_field)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        project_field.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectNext", project)
        end
      end

      def self.async_viewer_can_see?(permission, project_field)
        project_field.async_memex_project.then do |project|
          permission.typed_can_see?("ProjectNext", project)
        end
      end

      field :configuration, Objects::ProjectNextIterationFieldConfiguration, "Iteration configuration settings", null: false

      def self.load_from_global_id(id)
        Models::IterationField.load_from_global_id(id, v2: false)
      end
    end
  end
end
