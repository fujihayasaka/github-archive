# typed: true
# frozen_string_literal: true

module Memex
  class EditFormFieldComponent < ApplicationComponent
    with_collection_parameter :field

    class UnrecognizedTypeError < StandardError; end

    attr_reader :field, :memex, :values, :item, :readonly

    def initialize(field:, memex:, item:, values:, readonly:)
      @field = field
      @memex = memex
      @values = values
      @item = item
      @readonly = readonly
    end

    memoize def icon
      component.icon
    end

    memoize def authenticity_token
      authenticity_token_for(update_url, method: "PUT")
    end

    memoize def update_url
      update_memex_item_path(memex_id: memex.id)
    end

    memoize def component
      case field.data_type.to_sym
      when :text
        result = Memex::EditFormFieldTextComponent.new(value: @values[field.id], field: field, readonly: readonly)
      when :number
        result = Memex::EditFormFieldNumberComponent.new(value: @values[field.id], field: field, readonly: readonly)
      when :date
        result = Memex::EditFormFieldDateComponent.new(value: @values[field.id], field: field, readonly: readonly)
      when :single_select
        result = Memex::EditFormFieldSingleSelectComponent.new(value: @values[field.id], field: field, readonly: readonly)
      when :iteration
        result = Memex::EditFormFieldIterationComponent.new(value: @values[field.id], field: field, readonly: readonly)
      end

      raise UnrecognizedTypeError unless result
      result
    end
  end
end
