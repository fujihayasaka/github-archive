# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class ProjectV2
      include Helpers::ProjectV2Sorter

      # Creates a prefix object for global ids reducing repetition
      #
      Prefix = Struct.new(
        :prefix,
        :org,
        :user
      ) do
        def to_s
          prefix
        end
      end

      def self.async_api_can_access?(permission, object)
        unless object.respond_to?(:async_memex_project)
          raise Platform::Errors::Internal, "object must implement async_memex_project"
        end

        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.async_memex_project.then do |project|
          permission.typed_can_access?("ProjectV2", project)
        end
      end

      def self.async_viewer_can_see?(permission, object)
        unless object.respond_to?(:async_memex_project)
          raise Platform::Errors::Internal, "object must implement async_memex_project"
        end

        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        object.async_memex_project.then do |project|
          permission.typed_can_see?("ProjectV2", project)
        end
      end

      # Order objects given the order_by argument
      #
      def self.order_objects(objects, order_by = nil, omit_ordering: false)
        objects = objects.compact
        return ArrayWrapper.new([]) if objects.empty?

        return ArrayWrapper.new(objects) if order_by.nil?

        # In some cases objects are pre-sorted and just need direction applied
        return ArrayWrapper.new(
          order_by[:direction] == "ASC" ? objects : objects.reverse
        ) if omit_ordering

        ArrayWrapper.new(
          self.sort_objects(objects, order_by[:field], order_by[:direction])
        )
      end

      def self.sort_objects(objects, field, direction, viewer = nil)
        if field == "recently_viewed" && viewer && objects.all? { |o| o.is_a? MemexProject }
          ProjectV2Sorter.sort_projects_v2_by_recently_viewed(objects, viewer.id, direction)
        else
          objects.sort do |a, b|
            left, right = direction == "ASC" ? [a, b] : [b, a]

            result = left.read_attribute(field) <=> right.read_attribute(field)
            # If the values are the same, fall back on the ID
            result.nonzero? ? result : left.id <=> right.id
          end
        end
      end

      # Both the `LinkProjectV2ToTeam` and `UnlinkProjectV2FromTeam` mutations
      #   use the same checks for egress.
      def self.async_api_can_modify_team_project_link?(permission, project:, team:)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        project.async_owner.then do |owner|
          permission.access_allowed?(
            :link_team_project_v2,
            current_org: owner,
            resource: team,
            project: project,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Both the `LinkProjectV2ToTeam` and `UnlinkProjectV2FromTeam` mutations
      #   use the same validation for the parameters.
      def self.validate_update_team_project_link(
        viewer,
        project,
        team
      )
        unless project.owner == team.organization
          raise Errors::Unprocessable.new("Team and project must belong to the same organization")
        end

        if viewer.user?
          unless project.viewer_is_admin?(viewer) && team.member?(viewer)
            raise Errors::Forbidden.new(
              "The viewer must be a member of the team and have admin permissions on the project"
            )
          end
        elsif viewer.bot?
          installation = viewer.installation

          unless project.owner.projects_adminable_by?(installation) && team.visible_to?(installation)
            raise Errors::Forbidden.new(
              "The app must have write permissions on the organization projects and read access to organization members"
            )
          end
        end
      end

      def self.async_validate_project_by_number(project, number, permission)
        not_found_message = "Could not resolve to a ProjectV2 with the number #{number}."

        if project.nil?
          raise Errors::NotFound, not_found_message
        end

        permission.typed_can_see?("ProjectV2", project).then do |readable|
          if readable
            project
          else
            raise Errors::NotFound, not_found_message
          end
        end
      end

      def self.async_validate_readable_projects(projects, permission)
        Promise.all(
          projects.map do |project|
            permission.typed_can_see?("ProjectV2", project).then do |readable|
              readable ? project : nil
            end
          end
        ).then do |readable_projects|
          readable_projects.compact
        end
      end
    end
  end
end
