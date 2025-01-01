# typed: true
# frozen_string_literal: true

module Conduit
  class DismissedItemComponent < ApplicationComponent
    attr_reader :item
    delegate :resource_id, :resource_type, :event_type, :source, :event_id, :identifier, to: :item

    def initialize(feed_item:)
      @item = feed_item
    end

    private

    def type
      item.content_type.split(" ").last
    end
  end
end
