# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextIterationFieldIteration < Platform::Objects::Base
      description "Iteration field iteration settings for a project."

      required_capabilities [:mobile_only_schema_mask]

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

      field :id, String, "The iteration's ID.", null: false
      field :duration, Integer, "The iteration's duration in days", null: false
      field :start_date, Scalars::Date, "The iteration's start date", null: false
      field :title, String, "The iteration's title.", null: false
      field :title_html, String, "The iteration's html title.", null: false
    end
  end
end
