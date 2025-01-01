# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectNextSingleSelectFieldOption < Platform::Objects::Base
      description "Single select field option for a configuration for a project."

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

      field :name, String, "The option's name.", null: false
      field :id, String, "The option's ID.", null: false
      field :name_html, String, "The option's html name.", null: false
      field :color, Enums::ProjectV2SingleSelectFieldOptionColor, "The option's display color.", null: false, visibility: :under_development
      field :description, String, "The option's description.", null: false, visibility: :under_development
      field :description_html, String, "The option's html description.", null: false, visibility: :under_development
    end
  end
end
