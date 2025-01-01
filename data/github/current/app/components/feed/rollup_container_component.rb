# typed: true
# frozen_string_literal: true

module Feed
  class RollupContainerComponent < ApplicationComponent
    attr_reader :item

    def initialize(item:, **system_arguments)
      @item = item
    end
  end
end
