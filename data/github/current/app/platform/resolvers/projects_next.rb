# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ProjectsNext < Resolvers::Base

      type Connections.define(Platform::Objects::ProjectNext), null: false

      argument :query, String, "A project to search for under the the owner.", required: false
      argument :sort_by, Enums::ProjectNextOrderField,
        "How to order the returned projects.", required: false, default_value: "title"

      def resolve(query: nil, sort_by: "title")
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(@context[:viewer], @context[:oauth_app])

        if query.blank?
          return object.async_memex_projects.then do |memex_projects|
            async_owner = if object.is_a?(::Issue) || object.is_a?(::PullRequest)
              object.async_repository.then { |repo| repo.async_owner }
            else
              Promise.resolve(object)
            end

            async_owner.then do |owner|
              owner.async_accessible_memexes_scope(
                owner.memex_projects.active_projects.where("id IN (?)", memex_projects.map(&:id)),
                context[:viewer],
                  "read"
              ).then { |projects| sort_projects_next(projects, sort_by) }
            end
          end
        end

        Loaders::ProjectNextByQuery.load(@object, @context[:viewer], query).then { |projects| sort_projects_next(projects, sort_by) }
      end

      def sort_projects_next(projects, sort_by)
        ArrayWrapper.new(projects.compact&.sort_by { |p| p.send(sort_by.to_sym) || "" })
      end
    end
  end
end
