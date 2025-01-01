# typed: true
# frozen_string_literal: true

module SecurityCenter
  module SelectMenuComponentHelper
    def self.checked?(default_selected_slug:, qualifier:, query:, query_parser:, slug:, use_default_selected_slug_on_invalid_values:, valid_values:)
      return true if default_item_selected?(
        default_selected_slug: default_selected_slug,
        qualifier: qualifier,
        query: query,
        query_parser: query_parser,
        slug: slug,
        use_default_selected_slug_on_invalid_values: use_default_selected_slug_on_invalid_values,
        valid_values: valid_values
      )

      selected_items(qualifier: qualifier, query: query, query_parser: query_parser).include?(slug)
    end

    # @param items [Array<SecurityCenter::SelectMenu::Item>] Select menu items.
    def self.create_qualifier_to_valid_values_map(items: [])
      items.reduce({}) do |acc, item|
        acc[item.qualifier] ||= []
        acc[item.qualifier] << item.slug
        acc
      end
    end

    def self.default_item_selected?(default_selected_slug:, query:, query_parser:, qualifier:, slug:, use_default_selected_slug_on_invalid_values:, valid_values:)
      return false if default_selected_slug.nil?
      return slug == default_selected_slug unless query_parser.qualifier_exists?(query, qualifier)
      return false unless use_default_selected_slug_on_invalid_values

      # If we should display a check mark next to the the default item when the user requests invalid values
      #   and there's no overlap between what the user requested and all possible valid values,
      #   then check if the current item is the default.
      user_requested_values = query_parser.get_qualified_values(query, qualifier)
      user_requested_any_valid_values = (user_requested_values & valid_values).any?

      slug == default_selected_slug && !user_requested_any_valid_values
    end

    # Fills in a tab of a Primer::Experimental::SelectMenuComponent.
    # This method yields instances of SecurityCenter::SelectMenu::Item to the provided block (since the items must be rendered by the caller in ERB).
    #
    # @param items [Array<SecurityCenter::SelectMenu::Item>] Select menu items.
    # @param list [Primer::Experimental::SelectMenu::ListComponent] The list being built.
    def self.fill_tab(
      default_selected_slug:,
      is_multiselect:,
      items:,
      list:,
      qualifier_to_valid_values_map:,
      query:,
      query_parser:,
      use_default_selected_slug_on_invalid_values:,
      &block
    )
      return list.with_message { "Nothing to show" } if items.blank?

      items.each do |item|
        qualifier = item.qualifier
        slug = item.slug

        list.with_item(
          href: href(
            is_multiselect: is_multiselect,
            qualifier_to_select: qualifier,
            qualifiers_to_remove: qualifier_to_valid_values_map.keys,
            query: query,
            query_parser: query_parser,
            slug: slug
          ),
          selected: checked?(
            default_selected_slug: default_selected_slug,
            qualifier: qualifier,
            query: query,
            query_parser: query_parser,
            slug: slug,
            use_default_selected_slug_on_invalid_values: use_default_selected_slug_on_invalid_values,
            valid_values: qualifier_to_valid_values_map.fetch(qualifier)
          ),
          tag: :a,
          border_bottom: 0
        ) do
          block.call(item)
        end
      end
    end

    def self.query_string(is_multiselect:, qualifier_to_select:, qualifiers_to_remove:, query:, query_parser:, slug:)
      query_string = query

      if is_multiselect
        query_string = query_parser.add_or_remove(query_string, qualifier_to_select, slug)
      else
        # In the case a dropdown contains options for different qualifiers, the href for the current option should not include the other qualifiers.
        qualifiers_to_remove.each { |q| query_string = query_parser.remove_qualifier(query_string, q) }
        query_string = query_parser.add_or_replace(query_string, qualifier_to_select, slug)
      end

      query_string
    end

    def self.href(is_multiselect:, qualifier_to_select:, qualifiers_to_remove:, query:, query_parser:, slug:)
      query_parser.query_string_for_url(self.query_string(
        is_multiselect: is_multiselect,
        qualifier_to_select: qualifier_to_select,
        qualifiers_to_remove: qualifiers_to_remove,
        query: query,
        query_parser: query_parser,
        slug: slug
      ))
    end

    def self.query_clear_all(query:, query_parser:, qualifiers:)
      query_string = query
      qualifiers.each { |q| query_string = query_parser.remove_qualifier(query_string, q) }
      query_string
    end

    def self.href_clear_all(query:, query_parser:, qualifiers:)
      query_parser.query_string_for_url(self.query_clear_all(
        query: query,
        query_parser: query_parser,
        qualifiers: qualifiers,
      ))
    end

    def self.selected_items(qualifier:, query:, query_parser:)
      query_parser.get_qualified_values(query, qualifier).to_set
    end
  end
end
