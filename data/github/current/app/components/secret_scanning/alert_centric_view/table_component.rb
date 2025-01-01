# typed: true
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    class TableComponent < ApplicationComponent
      QUERY_PARSER = Search::Queries::SecurityCenter::SecretScanningQuery

      attr_reader :query_parser

      def initialize(
        alerts: [],
        blankslate: nil,
        closed_alert_count: 0,
        filter_option_paths: {},
        open_alert_count: 0,
        page: 1,
        query: "",
        scope: nil,
        custom_patterns_available: true,
        locked_repos: Set.new,
        **system_arguments
      )
        @alerts = alerts
        @blankslate = blankslate
        @closed_alert_count = closed_alert_count
        @filter_option_paths = filter_option_paths
        @open_alert_count = open_alert_count
        @page = page
        @query = query
        @scope = scope
        @custom_patterns_available = custom_patterns_available
        @locked_repos = locked_repos
        @show_owner = @scope.is_a?(Business)
        @show_repository = @scope.is_a?(Business) || @scope.is_a?(Organization)
        @show_alert_number = @scope.is_a?(Repository)
        @query_parser = QUERY_PARSER.new(query: query)
      end

      def pagination_results
        selected_token_state = QUERY_PARSER.get_qualified_values(@query, QUERY_PARSER::QUALIFIER_IS).first

        token_count = if selected_token_state == QUERY_PARSER::IS_OPEN
          @open_alert_count
        elsif selected_token_state == QUERY_PARSER::IS_CLOSED
          @closed_alert_count
        else
          @open_alert_count + @closed_alert_count
        end

        WillPaginate::Collection.new(@page, SecretScanningControllerHelper::PAGE_SIZE, token_count)
      end

      def show_table_body_blankslate?
        @blankslate.present? || QUERY_PARSER.has_duplicate_qualifiers?(@query)
      end

      def open_alert_href
        query_parser.get_is_state_href(QUERY_PARSER::IS_OPEN)
      end

      def closed_alert_href
        query_parser.get_is_state_href(QUERY_PARSER::IS_CLOSED)
      end

      def open_alert_selected
        query_parser.is_open_page?
      end

      def closed_alert_selected
        query_parser.is_closed_page?
      end
    end
  end
end
