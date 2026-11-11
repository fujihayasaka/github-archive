# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class AlertFilterComponent < ApplicationComponent
    # Current implemented filter types:
    # organization (business level)
    # repository (business and organization level)
    # ecosystem
    # package
    # manifest
    # severity
    attr_reader :alerts_page_path, :filter_type, :query_string, :item_list

    def initialize(alerts_page_path:, filter_type:, query_string:, item_list:, show_search_bar: true)
      @alerts_page_path = alerts_page_path
      @filter_type = filter_type
      @query_string = query_string
      @item_list = item_list
      @show_search_bar = show_search_bar
    end

    # This method is used to generate the query string for multiselect filters. It appends
    # new values to the current query string when they're selected, and removes them when
    # they're deselected.
    #
    # For example, if the current query string is "severity:high", selecting "low" will append
    # this value and update the query string to "severity:high,low". Then, deselecting "high"
    # will remove this value but preserve "low", resulting in the new query string "severity:low".
    #
    def query_string_for(qualifier, value)
      Search::Queries::SecurityCenter::DependabotAlertsQuery.add_or_remove(query_string, qualifier, value).presence
    end

    def query_string_without(qualifier)
      Search::Queries::SecurityCenter::DependabotAlertsQuery.remove_qualifier(query_string, qualifier).presence
    end

    memoize def query_hash
      Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(query_string)
    end

    def dependabot_alerts_path(q:)
      alerts_page_path.call(q: q)
    end

    def selected(slug)
      query_hash.fetch(filter_type.to_sym, []).any? { |val| val.casecmp?(slug) }
    end

    def any_selected?
      query_hash.fetch(filter_type.to_sym, []).any?
    end

    def filter_query(slug)
      query_string_for(filter_type.to_sym, slug)
    end

    memoize def truncation_length
      if item_list.any? { |item| item[:count].present? }
        175
      else
        230
      end
    end

    def filter_name
      return "organization" if @filter_type == "org"
      return "repository" if @filter_type == "repo"
      @filter_type
    end
  end
end
