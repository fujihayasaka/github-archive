# typed: true
# frozen_string_literal: true

module Compare
  class StatComponent < ApplicationComponent
    attr_reader :icon_name, :item_count

    def initialize(icon_name:, item_count:, pluralized_item_name:, description_suffix: nil)
      @icon_name = icon_name
      @item_count = item_count
      @pluralized_item_name = pluralized_item_name
      @description_suffix = description_suffix
    end

    def delimited_item_count
      number_with_delimiter(@item_count)
    end

    def pluralized_item_name
      pluralized_item_name = @pluralized_item_name.pluralize(@item_count)
      pluralized_item_name += " #{@description_suffix}" if @description_suffix
      pluralized_item_name
    end
  end
end
