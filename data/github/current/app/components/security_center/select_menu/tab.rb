# typed: true
# frozen_string_literal: true

module SecurityCenter
  module SelectMenu
    class Tab # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      attr_reader :id, :items, :title

      # @param id [String, nil] An HTML ID.
      # @param items [Array<SecurityCenter::SelectMenu::Item>] Information for each tab item.
      # @param title [String, nil] The name to display. Omit this if your menu only has a single tab.
      def initialize(id: nil, items: [], title: nil)
        @id = id
        @items = items
        @title = title
      end
    end
  end
end
