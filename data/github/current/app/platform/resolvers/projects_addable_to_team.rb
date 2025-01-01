# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ProjectsAddableToTeam < Platform::Resolvers::Projects
      def resolve(**args)
        object.async_organization.then do
          super_value = super

          # We use Team#projects instead of Team#visible_projects_for here,
          # because we're ultimately using this to figure out which projects
          # to _exclude_ from the list. There's no danger of exposing private
          # projects with this, because they'll already be filtered out of the
          # list we're excluding these projects from.
          team_project_ids = object.projects.pluck(:id)

          if team_project_ids.empty?
            # The team has no projects so we don't need to do any additional
            # filtering.
            super_value
          elsif super_value.is_a?(Helpers::ProjectsQuery)
            # Temporary hack until org project permissions are understood by
            # ElasticSearch.
            #
            # It's a search, so get the projects out of it and restrict them by
            # id.
            projects = super_value.query.execute.results.map { |result| result["_model"] }

            ArrayWrapper.new(
              projects.select { |project| team_project_ids.exclude?(project.id) },
            )
          else
            # It's a scope in a promise, so we can chain onto it.
            Promise.resolve(super_value).then do |scope|
              scope.where("projects.id NOT IN (?)", team_project_ids)
            end
          end
        end
      end

      def project_owner_from(team)
        team.organization
      end
    end
  end
end
