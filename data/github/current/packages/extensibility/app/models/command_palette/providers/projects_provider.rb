# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class ProjectsProvider < ApplicationProvider
      extend T::Sig

      def self.modes
        [:owner_repo_references, :projects]
      end

      def search(query)
        return [] unless scope_matches?
        return [] unless query_matches_allowed_types?("project", query: query)
        return [] unless query_matches_allowed_types?(query: query, filter: :author)

        org = nil
        if scope.organization?
          org = scope.organization
        elsif scope.repository?
          org = scope.repository.organization
        end

        classic_projects = ProjectsClassicSunset.projects_classic_ui_enabled?(current_user, org: org) ? project_query(query) : []
        memexes = memex_query(query)

        combined_results(classic_projects, memexes)
      end

      private

      # Returns a list of memex jump to results for the given query
      sig { params(query: String).returns(T::Array[MemexProject]) }
      def memex_query(query)
        return [] unless GitHub.projects_new_enabled?

        source = scope.repository || scope.owner

        source.search_memex_projects(
          query: Search::Queries::MemexProjectQuery.new(query),
          viewer: current_user,
        ).memex_projects
      end

      # Returns a list of project jump to results for the given query
      sig { params(query: String).returns(T::Array[Project]) }
      def project_query(query)
        project_query = build_project_query

        return [] unless project_query

        project_query.phrase = query
        project_query.execute.results.map do |result|
          result["_model"]
        end
      end

      # Returns a project query to be executed for the given scope
      sig { returns(T.nilable(Search::Queries::ProjectQuery)) }
      def build_project_query
        scope_query = if scope.repository?
          {
            repo_id: scope.repository.id,
            project_type: "repo"
          }
        elsif scope.organization?
          {
            org_id: scope.organization.id,
            project_type: "org",
            scoped: true
          }
        elsif scope.user?
          {
            user_id: scope.user.id,
            project_type: "user"
          }
        end

        Search::Queries::ProjectQuery.new({
          current_user: current_user,
          aggregations: :state
        }.merge(scope_query)) if scope_query.present?
      end

      sig { params(projects: T::Array[Project], memexes: T::Array[MemexProject]).returns(T::Array[CommandPalette::Result]) }
      def combined_results(projects, memexes)
        memexes.concat(projects).map do |record|
          Result.jump_to(record, context: context)
        end
      end
    end
  end
end
