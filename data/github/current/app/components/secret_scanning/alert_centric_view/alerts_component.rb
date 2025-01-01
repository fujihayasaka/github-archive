# typed: true
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    class AlertsComponent < ApplicationComponent
      include SecretScanning::Features::FeatureFlagHelper

      QUERY_PARSER = Search::Queries::SecurityCenter::SecretScanningQuery

      def initialize(
        alerts: [],
        blankslate: nil,
        closed_alert_count: 0,
        filter_option_paths: {},
        open_alert_count: 0,
        page: 1,
        query: "",
        user: nil,
        scope: nil,
        custom_patterns_available: true,
        show_org_level_suggestions: false,
        show_business_level_suggestions: false,
        show_user_repo_suggestions: false,
        locked_repos: Set.new,
        filter_suggestions_path: nil,
        menu_data_list: [],
        show_results_selector: false,
        show_incomplete_data_warning: false,
        unresolved_experimental_alert_count: nil
      )
        @alerts = alerts
        @blankslate = blankslate
        @closed_alert_count = closed_alert_count
        @filter_option_paths = filter_option_paths
        @open_alert_count = open_alert_count
        @page = page
        @query = query
        @user = user
        @scope = scope
        @custom_patterns_available = custom_patterns_available
        @show_org_level_suggestions = show_org_level_suggestions
        @show_business_level_suggestions = show_business_level_suggestions
        @show_user_repo_suggestions = show_user_repo_suggestions
        @locked_repos = locked_repos
        @filter_suggestions_path = filter_suggestions_path
        @menu_data_list = menu_data_list
        @query_parser = T.let(QUERY_PARSER.new(query: query, allow_results_category: show_results_selector), QUERY_PARSER)
        @show_results_selector = show_results_selector
        @show_incomplete_data_warning = show_incomplete_data_warning
        @unresolved_experimental_alert_count = unresolved_experimental_alert_count
      end

      sig { returns(T::Boolean) }
      def default_results_selected?
        return false if @query_parser.has_invalid_results_category?
        @query_parser.results_category == QUERY_PARSER::DEFAULT_RESULTS_CATEGORY
      end

      sig { returns(T::Boolean) }
      def experimental_results_selected?
        return false if @query_parser.has_invalid_results_category?
        @query_parser.results_category == QUERY_PARSER::EXPERIMENTAL_RESULTS
      end

      sig { returns(String) }
      def default_results_href
        @query_parser.get_results_category_href(QUERY_PARSER::DEFAULT_RESULTS_CATEGORY)
      end

      sig { returns(String) }
      def experimental_results_href
        @query_parser.get_results_category_href(QUERY_PARSER::EXPERIMENTAL_RESULTS)
      end

      sig { returns(T.nilable(Integer)) }
      def experimental_results_count
        @unresolved_experimental_alert_count
      end
    end
  end
end
