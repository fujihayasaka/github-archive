# typed: true
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    class TableHeaderComponent < ApplicationComponent
      include UrlHelpers

      QUERY_PARSER = Search::Queries::SecurityCenter::SecretScanningQuery

      attr_reader :closed_alert_count, :open_alert_count, :query, :repository, :custom_patterns_available, :show_organization, :show_repository, :filter_option_paths, :query_parser

      def initialize(
        closed_alert_count: 0,
        open_alert_count: 0,
        query: "",
        repository: nil,
        filter_option_paths: {},
        custom_patterns_available: false,
        show_owner: false,
        show_repository: false
      )
        @closed_alert_count = closed_alert_count
        @open_alert_count = open_alert_count
        @filter_option_paths = filter_option_paths
        @query = query
        @repository = repository
        @custom_patterns_available = custom_patterns_available
        @show_owner = show_owner
        @show_repository = show_repository
        @query_parser = QUERY_PARSER.new(query: query)
      end

      def show_repo_owner_suggestions?
        @show_owner
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

      def no_state_selected
        query_parser.is_no_state_page?
      end

      def show_resolution_filter?
        closed_alert_selected || no_state_selected
      end

      def repository_token_scanning_reopened_path
        helpers.repository_token_scanning_resolve_path(
          repository.owner,
          repository,
          resolution: "reopened"
        )
      end

      def mapped_resolution_options
        # Default to true to retain pre-existing behavior
        opts = QUERY_PARSER::RESOLUTION_OPTIONS
        unless custom_patterns_available
          opts = opts.reject { |item| item[:feature] == :custom_pattern }
        end

        opts.map do |item|
          SecurityCenter::SelectMenu::Item.new(**item.slice(:count, :description, :label, :qualifier, :slug))
        end
      end

      def mapped_validity_options
        opts = QUERY_PARSER::VALIDITY_OPTIONS

        opts.map do |item|
          SecurityCenter::SelectMenu::Item.new(**item.slice(:count, :description, :label, :qualifier, :slug))
        end
      end

      def mapped_bypass_options
        opts = QUERY_PARSER::BYPASSED_OPTIONS

        opts.map do |item|
          SecurityCenter::SelectMenu::Item.new(**item.slice(:count, :description, :label, :qualifier, :slug))
        end
      end
    end
  end
end
