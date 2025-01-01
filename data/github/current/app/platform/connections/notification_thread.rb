# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class NotificationThread < Connections::Base
      description "A list of notification threads."

      total_count_field

      field :first_item_offset, Integer, null: false, visibility: :internal, description: "Offset of first item in the list"
      def first_item_offset
        @object.try(:first_item_offset) || 1
      end
    end
  end
end
