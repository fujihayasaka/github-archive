# typed: true
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    class AlertsComponent < ApplicationComponent
      extend T::Sig
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
        show_confidence_selector: false,
        show_incomplete_data_warning: false,
        unresolved_other_alert_count: nil
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
        @query_parser = T.let(QUERY_PARSER.new(query: query, allow_confidence: show_confidence_selector), QUERY_PARSER)
        @show_confidence_selector = show_confidence_selector
        @show_incomplete_data_warning = show_incomplete_data_warning
        @unresolved_other_alert_count = unresolved_other_alert_count
      end

      sig { returns(T::Boolean) }
      def high_confidence_selected?
        return false if @query_parser.has_invalid_confidence?
        @query_parser.confidence == QUERY_PARSER::HIGH_CONFIDENCE
      end

      sig { returns(T::Boolean) }
      def other_confidence_selected?
        return false if @query_parser.has_invalid_confidence?
        @query_parser.confidence == QUERY_PARSER::OTHER_CONFIDENCE
      end

      sig { returns(String) }
      def high_confidence_href
        @query_parser.get_confidence_href(QUERY_PARSER::HIGH_CONFIDENCE)
      end

      sig { returns(String) }
      def other_confidence_href
        @query_parser.get_confidence_href(QUERY_PARSER::OTHER_CONFIDENCE)
      end

      sig { returns(T.nilable(Integer)) }
      def other_confidence_count
        @unresolved_other_alert_count
      end
    end
  end
end
