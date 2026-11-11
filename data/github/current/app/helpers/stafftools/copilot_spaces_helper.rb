# typed: true
# frozen_string_literal: true

module Stafftools
  module CopilotSpacesHelper
    # Public: Format the base role for display in Copilot Spaces stafftools views.
    #
    # base_role - String representing the base role of the space
    #
    # Returns a String that represents the formatted base role label.
    def format_base_role_label(base_role)
      case base_role
      when "custom_copilot_reader"
        "Base Role: Viewer"
      when "custom_copilot_writer"
        "Base Role: Editor"
      when "custom_copilot_admin"
        "Base Role: Admin"
      else
        "Base Role: #{base_role.humanize}"
      end
    end

    # Public: Get the visibility text for a Copilot Space.
    #
    # space - The CopilotSpace object
    # is_org_context - Boolean indicating if this is in organization context
    #
    # Returns a String with the visibility text.
    def space_visibility_text(space, is_org_context: false)
      if space.base_role == "none"
        "Private"
      else
        is_org_context ? "Org Public" : "Public"
      end
    end

    # Public: Get the visibility scheme for a Copilot Space.
    #
    # space - The CopilotSpace object
    #
    # Returns a Symbol representing the label scheme.
    def space_visibility_scheme(space)
      space.base_role == "none" ? :secondary : :accent
    end

    # Public: Get the icon name for a resource type.
    #
    # resource_type - String representing the resource type
    #
    # Returns a String with the icon name.
    def resource_type_icon_name(resource_type)
      case resource_type
      when "github_file"
        "file"
      when "github_repository"
        "repo"
      when "github_issue"
        "issue-opened"
      when "github_pull_request"
        "git-pull-request"
      when "web_page"
        "globe"
      else
        "file"
      end
    end

    # Public: Get options for space visibility/access level selection dropdowns.
    # These control who can access the entire space.
    #
    # Returns array of options for select dropdown.
    def copilot_space_visibility_options
      [
        ["Private (No access)", "none"],
        %w[Viewer custom_copilot_reader],
        %w[Editor custom_copilot_writer],
        %w[Admin custom_copilot_admin]
      ]
    end

    # Public: Get options for individual collaborator role selection dropdowns.
    # These control what permissions a specific collaborator has within the space.
    #
    # Returns array of options for select dropdown.
    def copilot_space_collaborator_role_options
      [
        %w[Viewer custom_copilot_reader],
        %w[Editor custom_copilot_writer],
        %w[Admin custom_copilot_admin]
      ]
    end

    # Public: Format collaborator role names for display.
    #
    # role_name - String representing the role name (e.g. "custom_copilot_reader")
    #
    # Returns a String with the formatted role label.
    def format_collaborator_role_label(role_name)
      case role_name
      when "custom_copilot_reader"
        "User Role: Viewer"
      when "custom_copilot_writer"
        "User Role: Editor"
      when "custom_copilot_admin"
        "User Role: Admin"
      else
        "User Role: #{role_name.humanize}"
      end
    end
  end
end
