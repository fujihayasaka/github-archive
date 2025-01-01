# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextIterationFieldConfiguration < Platform::Objects::Base
      description "Iteration field configuration for a project."

      mobile_only true

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

      field :duration, Integer, "The iteration's duration in days", null: false
      field :start_day, Integer, "The iteration's start day of the week", null: false
      field :iterations, [Objects::ProjectNextIterationFieldIteration, null: false], "The iteration's iterations", null: false
      field :completed_iterations, [Objects::ProjectNextIterationFieldIteration, null: false], "The iteration's completed iterations", null: false

    end
  end
end
