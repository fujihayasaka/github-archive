# typed: true
# frozen_string_literal: true

module SecurityCenter
  class SelectMenuContentComponent < ApplicationComponent
    # @param tabs [Array<SecurityCenter::SelectMenu::Tab>] Information for each tab of the menu.
    def initialize(query_parser:, default_selected_slug: nil, is_multiselect: false, query: "", tabs: [])
      @query_parser = query_parser
      @default_selected_slug = default_selected_slug
      @is_multiselect = is_multiselect
      @query = query
      @tabs = tabs

      @qualifier_to_valid_values_map = SecurityCenter::SelectMenuComponentHelper
        .create_qualifier_to_valid_values_map(items: tabs.map(&:items).flatten)
    end
  end
end
