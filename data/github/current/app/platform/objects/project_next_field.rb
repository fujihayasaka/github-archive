# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextField < Platform::Objects::Base
      implements Platform::Interfaces::ProjectNextFieldCommon

      required_capabilities [:mobile_only_schema_mask]
      model_name "MemexProjectColumn"
      description "A field inside a project."

      minimum_accepted_scopes ["read:org"]

      implements_node templates: [
          [:opnf, :org_id, :project_next_id, :project_next_field_id],
          [:upnf, :user_id, :project_next_id, :project_next_field_id]
        ],
        as: "PNF",
        ready_date: Platform::Interfaces::ProjectNextFieldCommon::PROJECT_NEXT_COHORT do |project_next_field|
        project_next_field.async_memex_project.then do |project_next|
          case project_next.owner_type
          when "Organization"
            {
              prefix: :opnf,
              org_id: project_next.owner_id,
              project_next_id: project_next.id,
              project_next_field_id: project_next_field.id
            }
          when "User"
            {
              prefix: :upnf,
              user_id: project_next.owner_id,
              project_next_id: project_next.id,
              project_next_field_id: project_next_field.id
            }
          else
            raise Platform::Errors::Internal, "Unexpected project owner: #{project_next.owner_type.inspect}"
          end
        end
      end

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
    end
  end
end
