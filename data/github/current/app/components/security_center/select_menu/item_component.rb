# typed: true
# frozen_string_literal: true

module SecurityCenter
  module SelectMenu
    class ItemComponent < ApplicationComponent
      attr_reader :item

      # @param item [SecurityCenter::SelectMenu::Item] Item information.
      def initialize(item:)
        @item = item
      end
    end
  end
end
