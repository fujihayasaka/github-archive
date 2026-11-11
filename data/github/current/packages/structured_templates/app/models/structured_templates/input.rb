# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class Input
    include ActiveModel::Validations
    include StructuredTemplates::ValidationHelpers

    REQUIRED_ATTRIBUTES = [{ id: :label, type: "String" }].freeze

    OPTIONAL_ATTRIBUTES = [
      { id: :description, type: "String" },
      { id: :placeholder, type: "String" },
      { id: :value, type: "String" },
    ].freeze

    OPTIONAL_VALIDATIONS = [{ id: :required, type: "Boolean" }, { id: :validations, type: "Hash" }].freeze

    validates_each :label do |record, key, value|
      validate_required_attributes(REQUIRED_ATTRIBUTES, record, key, value)
    end

    validates_each :description, :placeholder, :value do |record, key, value|
      next if value.nil?
      validate_optional_attributes(OPTIONAL_ATTRIBUTES, record, key, value)
    end

    validates_each :validations, :required do |record, key, value|
      next if value.nil?
      validate_optional_attributes(OPTIONAL_VALIDATIONS, record, key, value)
    end

    validate :no_extra_keys
    validate :no_extra_attributes
    validate :id_is_string
    validate :no_forbidden_label

    attr_reader :type, :id, :label, :description, :required, :placeholder, :input, :validations, :auto_id
    attr_accessor :value

    def initialize(input:)
      @input = input
      @type = @input.dig("type")

      @label = @input.dig("attributes", "label")
      @id, @auto_id = build_id(@input, @label)
      @description = @input.dig("attributes", "description")
      @required = false_if_undefined(@input, "validations", "required")
      @validations = @input.dig("validations")
      @placeholder = @input.dig("attributes", "placeholder")
      @value = @input.dig("attributes", "value")
    end

    def platform_type_name
      "IssueFormElementInput"
    end

    private

    def no_extra_attributes
      check_extraneous_attributes(REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES, @input["attributes"]&.keys)
    end
  end
end
