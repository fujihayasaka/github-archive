# typed: true
# frozen_string_literal: true

module Memex
  class EditFormFieldDateComponent < ApplicationComponent
    attr_reader :value, :field, :readonly

    def initialize(value:, field:, readonly:)
      @value = value
      @field = field
      @readonly = readonly
    end

    memoize def icon
      Primer::Beta::Octicon.new("calendar")
    end

    def formatted
      @formatted ||= Date.parse(value["value"]).strftime("%b %-d, %Y") unless value.nil?
    end

    def raw
      @raw ||= Date.parse(value["value"]).strftime("%F") unless value.nil?
    end
  end
end
