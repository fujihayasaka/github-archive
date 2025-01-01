# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ProjectsV2 < Resolvers::Base
      include Helpers::ProjectV2Sorter

      type Connections.define(Platform::Objects::ProjectV2), null: false

      argument :query, String, "A project to search for under the the owner.", required: false

      argument :use_full_term_query,
        Boolean,
        "Search project titles that match the entire query string",
        required: false,
        default_value: false,
        visibility: :internal

      argument :order_by, Inputs::ProjectV2Order,
        "How to order the returned projects.", required: false, default_value: { field: "number", direction: "DESC" }

      argument :min_permission_level, Enums::ProjectV2PermissionLevel, "Filter projects based on user role.", required: false, default_value: "read"

      def resolve(query: nil, order_by: { field: "number", direction: "DESC" }, min_permission_level: "read", use_full_term_query: false)
        return sort_projects_v2(object.projects_for_viewer(context[:viewer]), order_by, query, context[:viewer]) if object.is_a?(::IssueTemplate)

        if query.blank?
          async_owner = if object.is_a?(::Issue) || object.is_a?(::PullRequest)
            object.async_repository.then { |repo| repo.async_owner }
          else
            Promise.resolve(object)
          end

          return async_owner.then do |owner|
            owner.async_accessible_memexes_scope(
              object.memex_projects,
              context[:viewer],
              min_permission_level
            ).then { |projects| sort_projects_v2(projects, order_by, query, context[:viewer]) }
          end
        end

        Loaders::ProjectV2ByQuery.load(object, context[:viewer], query, min_permission_level, use_full_term_query).then do |projects|
          sort_projects_v2(projects, order_by, query, context[:viewer])
        end
      end
    end
  end
end
