# typed: true
# frozen_string_literal: true

module Organizations
  module Settings
    # Extracting from the Orgs::Settings::MemberPrivilegesView
    # to add the new portion of UI using ViewComponents instead of adding to ViewModel logic
    class OrgProjectsRoleSettingComponent < ApplicationComponent
      attr_reader :organization
      def initialize(organization:)
        @organization = organization
      end

      BaseRoleOption = T.type_alias { { heading: String, selected: T::Boolean, value: String, description: String } }

      sig { returns(T::Array[BaseRoleOption]) }
      memoize def default_projects_base_role_select_list
        [
          {
            heading: "No access",
            description: "Members will only be able to see projects that are made public. To give an organization member additional access, they can be added as part of a team or as a collaborator.",
            value: "none",
            selected: current_org_projects_base_role == "none",
          },
          {
            heading: "Read",
            description: "Members can see projects.",
            value: "project_reader",
            selected: current_org_projects_base_role == "project_reader",
          },
          {
            heading: "Write",
            description: "Members can see and make changes to projects.",
            value: "project_writer",
            selected: current_org_projects_base_role == "project_writer",
          },
          {
            heading: "Admin",
            description: "Members can see, make changes to, and add new collaborators to projects.",
            value: "project_admin",
            selected: current_org_projects_base_role == "project_admin",
          },
        ]
      end

      sig { returns(String) }
      def default_projects_base_role_button_text
        default_projects_base_role_selected_option[:heading]
      end

      sig { returns(BaseRoleOption) }
      def default_projects_base_role_selected_option
        T.must_because(default_projects_base_role_select_list.find { |s| s[:selected] }) { "There should always be a default selected option" }
      end

      def dialog_id
        "project-roles-dialog"
      end

      memoize def dialog_description
        if affected_org_projects_count > 0
          "This will change the base permissions for #{affected_org_projects_count} #{correct_pluralization}."
        else
          "This won't affect any existing projects."
        end
      end

      private

      memoize def current_org_projects_base_role
        @organization.projects_base_role
      end

      memoize def affected_org_projects_count
        @organization.projects_without_base_role_set_count
      end

      memoize def correct_pluralization
        affected_org_projects_count == 1 ? "project" : "projects"
      end
    end
  end
end
