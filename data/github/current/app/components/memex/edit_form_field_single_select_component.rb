# typed: true
# frozen_string_literal: true

module Memex
  class EditFormFieldSingleSelectComponent < ApplicationComponent
    attr_reader :value, :field, :readonly

    def initialize(value:, field:, readonly:)
      @value = value
      @field = field
      @readonly = readonly
    end

    memoize def icon
      Primer::Beta::Octicon.new("check-circle")
    end

    def current_selection
      @value["id"] unless !(!@value.nil? && @value.key?("id"))
    end

    def current_value
      field.settings_options.find { |v| v["id"] == value["id"] } unless value.nil?
    end
  end
end
