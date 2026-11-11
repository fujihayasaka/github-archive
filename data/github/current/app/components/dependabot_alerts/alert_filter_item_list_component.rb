# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class AlertFilterItemListComponent < AlertFilterComponent
    MORE_FILTER_OPTIONS_KEY = Search::Queries::DependabotAlertsFilterQuery::MORE_FILTER_OPTIONS_KEY.freeze

    def initialize(alerts_page_path:, filter_type:, query_string:, item_list:)
      @alerts_page_path = alerts_page_path
      @filter_type = filter_type
      @query_string = query_string
      @item_list = item_list

      @has_more_items = false
      item_list.index { |item| item[:slug] == MORE_FILTER_OPTIONS_KEY }.tap do |index|
        next if index.nil?

        @has_more_items = true
        @item_list.delete_at(index)
      end
    end

    def selected_items
      query_hash.fetch(filter_type.to_sym, [])
    end
  end
end
