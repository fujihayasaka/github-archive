# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Projects < Resolvers::Base

      type Connections::Project, null: false

      argument :order_by, Inputs::ProjectOrder, "Ordering options for projects returned from the connection", required: false
      argument :search, String, "Query to search projects by, currently only searching by name.", required: false
      argument :states, [Enums::ProjectState], "A list of states to filter the projects by.", required: false
      argument :include_private, Boolean, "Whether to only include public projects.", required: false, visibility: :internal, default_value: true

      def resolve(**arguments)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(context[:viewer], context[:oauth_app], context[:user_agent]) do
          return Project.none
        end

        arguments[:include_private] = true if arguments[:include_private].nil?
        GitHub.dogstats.distribution_time("projects.dist.resolver") do
          owner = project_owner_from(object)
          return Project.none if owner.is_a?(Repository) && !owner.repository_projects_enabled?
          return Project.none if owner.is_a?(Organization) && !owner.organization_projects_enabled?
          return Project.none unless context[:permission].can_list_projects?(owner)

          helper = Helpers::ProjectsQuery.new(owner, arguments, context[:viewer])

          # TODO: Also need to check to see if Elastic search is available.
          if helper.name_filter.present?
            helper
          else
            scope = if arguments[:include_private]
              owner.visible_projects_for(context[:viewer])
            else
              case owner
              when Repository
                if owner.public?
                  owner.projects
                else
                  Project.none
                end
              when Organization, User
                owner.projects.where(public: true)
              end
            end

            if helper.state_filter.present?
              scope = case helper.state_filter
              when "open"
                scope.open_projects
              when "closed"
                scope.closed_projects
              when "public"
                scope.public_projects
              when "private"
                scope.private_projects
              end
            end

            # the name filter is only used if elastic search is not available
            # and will not do partial matching, only full text match
            if helper.name_filter.present?
              scope = scope.where(name: helper.name_filter)
            end

            if helper.order_by_field_valid? && helper.order_by_direction_valid?
              scope = scope.order("projects.#{helper.order_by_field} #{helper.order_by_direction}")
            end

            scope
          end
        end
      end

      # Override in subclasses whose parent is not the project owner.
      def project_owner_from(parent)
        parent
      end
    end
  end
end
