# typed: true
# frozen_string_literal: true

module SecurityCenter
  class SelectMenuComponent < ApplicationComponent
    # @param tabs [Array<SecurityCenter::SelectMenu::Tab>] Information for each tab of the menu.
    def initialize(
      button_text:,
      query_parser:,
      clear_item_text: nil,
      show_clear: false,
      clear_path: nil,
      default_selected_slug: nil,
      header: nil,
      is_multiselect: false,
      query: "",
      tabs: [],
      use_default_selected_slug_on_invalid_values: false,
      src: nil,
      **system_arguments
    )
      @button_text = button_text
      @query_parser = query_parser
      @clear_item_text = clear_item_text || "Clear #{button_text.downcase.pluralize}"
      @show_clear = show_clear
      @clear_path = clear_path
      @default_selected_slug = default_selected_slug
      @header = header
      @is_multiselect = is_multiselect
      @query = query
      @tabs = tabs
      @use_default_selected_slug_on_invalid_values = use_default_selected_slug_on_invalid_values
      @src = src
      @system_arguments = system_arguments

      @qualifier_to_valid_values_map = SecurityCenter::SelectMenuComponentHelper
        .create_qualifier_to_valid_values_map(items: tabs.map(&:items).flatten)
    end

    def show_clear_button?
      @show_clear
    end

    def clear_href
      @clear_path if @clear_path.present?
    end
  end
end
