# typed: true
# frozen_string_literal: true

module Memex
  class EditFormFieldIterationComponent < ApplicationComponent
    NO_ITERATION_SELECTED = "No iteration selected"

    attr_reader :value, :field, :readonly

    def initialize(value:, field:, readonly:)
      @value = value
      @field = field
      @readonly = readonly
    end

    def current_selection
      @value["id"] if @value
    end

    memoize def current_value
      return if value.nil?

      settings_iterations_objects_all.find { |v| v.id == value["id"] }
    end

    def archived_title
      current_value&.title || NO_ITERATION_SELECTED
    end

    def choose_prompt
      "Choose an iteration ..."
    end

    memoize def settings_iterations_objects_all
      field.settings_iterations_objects_all
    end
  end
end
