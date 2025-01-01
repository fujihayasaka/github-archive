# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class Checkbox
    include ActiveModel::Validations
    include StructuredTemplates::ValidationHelpers

    RANDOM_BYTES = 6

    REQUIRED_ATTRIBUTES = [
      { id: :label, type: "String" },
    ].freeze

    OPTIONAL_ATTRIBUTES = [
      { id: :required, type: "Boolean" },
      { id: :id, type: "String" },
    ].freeze

    validates_each :label do |record, key, val|
      validate_required_attributes(REQUIRED_ATTRIBUTES, record, key, val)
    end

    validates_each :id, :required do |record, key, val|
      next if val.nil?
      validate_optional_attributes(OPTIONAL_ATTRIBUTES, record, key, val)
    end

    validate :no_extra_attributes

    attr_reader :id, :type, :label, :required, :input

    def initialize(input:)
      @input = input
      @type = "checkbox"

      @label = @input["label"]
      @id, _ = build_id(@input, @label)
      @required = false_if_undefined(@input, "required")
    end

    def required?
      required
    end

    private

    def no_extra_attributes
      return unless @input.is_a?(Hash)

      check_extraneous_attributes(REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES, @input.keys)
    end
  end
end
