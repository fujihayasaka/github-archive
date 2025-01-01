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
        show_campaign_filter: false,
        show_assignee_filter: false,
        show_business_level_suggestions: false,
        show_user_repo_suggestions: false,
        locked_repos: Set.new,
        filter_suggestions_path: nil,
        menu_data_list: [],
        show_results_selector: false,
        show_plaid_ui_filters: false,
        show_incomplete_data_warning: false,
        unresolved_generic_alert_count: nil
      )
        @alerts = alerts
        @fallback_blankslate = blankslate
        @closed_alert_count = closed_alert_count
        @filter_option_paths = filter_option_paths
        @open_alert_count = open_alert_count
        @page = page
        @query = query
        @user = user
        @scope = scope
        @custom_patterns_available = custom_patterns_available
        @show_org_level_suggestions = show_org_level_suggestions
        @show_campaign_filter = show_campaign_filter
        @show_assignee_filter = show_assignee_filter
        @show_business_level_suggestions = show_business_level_suggestions
        @show_user_repo_suggestions = show_user_repo_suggestions
        @locked_repos = locked_repos
        @filter_suggestions_path = filter_suggestions_path
        @menu_data_list = menu_data_list
        @query_parser = T.let(QUERY_PARSER.new(query: query, allow_results_category: show_results_selector), QUERY_PARSER)
        @show_results_selector = show_results_selector
        @show_plaid_ui_filters = show_plaid_ui_filters
        @show_incomplete_data_warning = show_incomplete_data_warning
        @unresolved_generic_alert_count = unresolved_generic_alert_count
      end

      sig { returns T.nilable(Symbol) }
      def blankslate
        return SecretScanningControllerHelper::BLANKSLATE_INVALID_QUERY unless @query_parser.is_valid?
        @fallback_blankslate
      end

      sig { returns(T::Boolean) }
      def default_results_selected?
        return false if @query_parser.has_invalid_results_category?
        @query_parser.results_category == QUERY_PARSER::DEFAULT_RESULTS_CATEGORY
      end

      sig { returns(T::Boolean) }
      def generic_results_selected?
        return false if @query_parser.has_invalid_results_category?
        @query_parser.results_category == QUERY_PARSER::GENERIC_RESULTS
      end

      sig { returns(String) }
      def default_results_href
        @query_parser.get_results_category_href(QUERY_PARSER::DEFAULT_RESULTS_CATEGORY)
      end

      sig { returns(String) }
      def generic_results_href
        @query_parser.get_results_category_href(QUERY_PARSER::GENERIC_RESULTS)
      end

      sig { returns(T.nilable(Integer)) }
      def generic_results_count
        @unresolved_generic_alert_count
      end

      sig { returns(String) }
      def results_category_query
        if generic_results_selected?
          "#{QUERY_PARSER::QUALIFIER_RESULTS_CATEGORY}:#{QUERY_PARSER::GENERIC_RESULTS}"
        else
          "#{QUERY_PARSER::QUALIFIER_RESULTS_CATEGORY}:#{QUERY_PARSER::DEFAULT_RESULTS}"
        end
      end
    end
  end
end
