# typed: true
# frozen_string_literal: true

module SecurityCenter
  module SelectMenu
    class ListComponent < ApplicationComponent
      TEST_SELECTOR = "security-center-select-menu-list"
      ITEM_TEST_SELECTOR = "security-center-select-menu-list-item"

      Data = Struct.new(:menu_id, :options, keyword_init: true) do
        def initialize(menu_id:, options:)
          raise ArgumentError, "menu_id must be of type String" unless menu_id.is_a?(String)
          raise ArgumentError, "options must be an Array of type OptionData" unless options.is_a?(Array) && options.all? { |c| c.is_a?(OptionData) }
          super
        end
      end

      OptionData = Struct.new(:text, :href, :description, :selected, keyword_init: true) do
        def initialize(text:, href:, description: nil, selected: false)
          raise ArgumentError, "text must be of type String" unless text.is_a?(String)
          raise ArgumentError, "href must be of type String" unless href.is_a?(String)
          raise ArgumentError, "description must be of type String" unless description.nil? || description.is_a?(String)
          raise ArgumentError, "selected must be of type TrueClass or FalseClass" unless [true, false].include? selected
          super
        end
      end

      def initialize(data)
        raise ArgumentError, "data must be of type #{Data}" unless data.is_a?(Data)
        @menu_id = data.menu_id
        @options = data.options
      end
    end
  end
end
