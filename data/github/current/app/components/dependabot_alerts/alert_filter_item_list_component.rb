# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class AlertFilterItemListComponent < AlertFilterComponent
    def initialize(alerts_page_path:, filter_type:, query_string:, item_list:)
      @alerts_page_path = alerts_page_path
      @filter_type = filter_type
      @query_string = query_string
      @item_list = item_list
    end

    def selected_items
      query_hash.fetch(filter_type.to_sym, [])
    end
  end
end
