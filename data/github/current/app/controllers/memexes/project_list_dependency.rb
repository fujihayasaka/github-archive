# typed: true
# frozen_string_literal: true

module Memexes
  module ProjectListDependency
    include MemexesHelper
    include ProjectsHelper
    extend ActiveSupport::Concern
    extend T::Helpers
    requires_ancestor { ApplicationController }

    MEMEX_INDEX_LIMIT = 30

    def list_projects(event = nil, xhr: false, recently_visited_projects: [])
      return nil if list_params[:query].blank? && !xhr

      parsed_query = Search::Queries::MemexProjectQuery.new(
        list_params[:query] || ""
      )

      filter_ids = if recently_visited_projects.any?
        recently_visited_projects.pluck(:id)
      else
        source.respond_to?(:memex_projects) ? source.memex_projects.pluck(:id) : []
      end

      search_result = source.search_memex_projects(
        query: parsed_query,
        viewer: current_user,
        cursor: list_params[:cursor],
        sort_query_cursor: list_params[:sort_query_cursor],
        limit: MEMEX_INDEX_LIMIT,
        filter_ids: filter_ids,
        recently_visited_projects: recently_visited_projects,
      )

      projects = search_result.memex_projects
      projects = cap_filter.authorized_resources(projects) if cap_filter.present? && current_user&.feature_enabled?(:cap_filter_projects_dashboard)
      write_accessible_project_ids = MemexProject.async_filter_accessible_memexes(current_user, projects, "write").sync.pluck(:id)

      return {
        context: source.class,
        projects: projects,
        write_accessible_project_ids: write_accessible_project_ids,
        owner: memex_owner,
        has_next_page: search_result.has_next_page?,
        query: memex_owner.organization? ? parsed_query.stringify : parsed_query,
        cursor: search_result.next_page_cursor,
        sort_query_cursor: search_result.sort_query_cursor,
        load_more_path: load_more_path
      } if xhr

      publish_memex_event(event, list_params[:query]) unless event.nil?

      {
        context: source.class,
        project_owner: memex_owner,
        source: source,
        memexes: projects,
        write_accessible_project_ids: write_accessible_project_ids,
        has_next_page: search_result.has_next_page?,
        cursor: search_result.next_page_cursor,
        sort_query_cursor: search_result.sort_query_cursor,
        parsed_query: parsed_query,
        open_memex_count: search_result.total_open_count,
        closed_memex_count: search_result.total_closed_count,
        memex_count: projects.count,
        has_any_memex_projects: source.memex_projects.any?,
        show_templates_index: memex_owner.is_a?(Organization),
      }
    end

    def source
      raise NotImplementedError
    end

    def memex_owner
      raise NotImplementedError
    end

    def load_more_path
      raise NotImplementedError
    end

    private

    def list_params
      @list_params ||= params.permit(
        :query,
        :cursor,
        :sort_query_cursor,
        :type,
        :user_id,
        :repository,
        :org,
        :client_uid,
        :team_slug,
        :is_search,
        :graphql_query_trace,
        :xhr_stats,
      ).to_hash.deep_symbolize_keys
    end

    def publish_memex_event(name, query, memex: nil)
      repository = if source.is_a?(Repository)
        source
      else
        current_path = Rails.application.routes.recognize_path(request.path)
        if current_path && current_path[:controller] == "repos/memexes" && current_path[:action] == "index"
          memex_owner.repositories.find_by_name(current_path[:repository])
        else
          nil
        end
      end

      GlobalInstrumenter.instrument("memex_event",
        {
          actor: current_user,
          memex_project: memex,
          memex_project_column: nil,
          memex_project_item: nil,
          name: name,
          ui: nil,
          context: query,
          memex_project_view: nil,
          repository: repository
        }
      )
    end

  end
end
