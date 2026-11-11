# typed: strict
# frozen_string_literal: true

module IssuesDashboardSurface
  class SearchConfig
    include DateMacroHelper
    include UrlHelpers

    ISSUES_QUERIES = T.let({
      "assigned" => Queries::ASSIGNED_QUERY,
      "created" => Queries::CREATED_QUERY,
      "mentioned" => Queries::MENTIONED_QUERY,
      "recent" => Queries::RECENT_QUERY,
    }.freeze, T::Hash[String, String])

    sig { returns(T.untyped) }
    attr_reader :params, :path

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { params(params: T.untyped, path: String, current_user: T.nilable(User)).returns(SearchConfig) }
    def self.from_params(params, path, current_user: nil)
      new(params, path, current_user: current_user)
    end

    sig { params(params: T.untyped, path: String, current_user: T.nilable(User)).void }
    def initialize(params, path, current_user: nil)
      @params = params
      @path = path
      @current_user = current_user
    end

    sig { returns(String) }
    def es_query
      replace_today_macro(query_value)
    end

    sig { returns(String) }
    private def query_value
      if params[:q].present?
        params[:q].to_s.strip
      else
        key = path_query_key
        return saved_view_query || default_query unless key

        ISSUES_QUERIES.fetch(key.to_s)
      end
    end

    sig { returns(T.nilable(String)) }
    private def saved_view_query
      saved_view_id = params[:saved_view_id]
      user = current_user
      return unless saved_view_id.present? && user

      shortcut = user.dashboard&.shortcuts&.find_by(id: saved_view_id)
      shortcut&.compressed_query.presence
    end

    sig { returns(T.nilable(Symbol)) }
    private def path_query_key
      case path
      when issues_dashboard_surface_assigned_path  then :assigned
      when issues_dashboard_surface_created_path   then :created
      when issues_dashboard_surface_mentioned_path then :mentioned
      when issues_dashboard_surface_recent_path    then :recent
      end
    end

    sig { returns(String) }
    private def default_query
      Queries::ASSIGNED_QUERY
    end

    sig { returns(Integer) }
    def maximum_result_limit
      25
    end

    sig { returns(Integer) }
    def page
      (params[:page] || 1).to_i
    end
  end
end
