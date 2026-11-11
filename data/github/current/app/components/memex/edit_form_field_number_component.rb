# typed: true
# frozen_string_literal: true

module Memex
  class EditFormFieldNumberComponent < ApplicationComponent
    attr_reader :value, :field, :readonly

    def initialize(value:, field:, readonly:)
      @value = value
      @field = field
      @readonly = readonly
    end

    memoize def icon
      Primer::Beta::Octicon.new("number")
    end

    def raw
      @raw ||= format_value_for_display unless value.nil?
    end

    private

    def format_value_for_display
      value["value"] % 1 == 0 ? value["value"].to_i : value["value"].to_f
    end
  end
end
