# typed: true
# frozen_string_literal: true

module Conduit
  class DismissItemComponent < ApplicationComponent
    renders_one :body

    attr_reader :item
    delegate :resource_id, :resource_type, :event_type, :source, :event_id, :identifier, to: :item

    def initialize(item:)
      @item = item
    end
  end
end
