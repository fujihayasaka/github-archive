# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class Dropdown < InputBase
    include ActiveModel::Validations
    include StructuredTemplates::ValidationHelpers

    REQUIRED_ATTRIBUTES = [
      { id: :options, type: "Array" },
      { id: :label, type: "String" },
    ].freeze

    OPTIONAL_ATTRIBUTES = [
      { id: :description, type: "String" },
      { id: :multiple, type: "Boolean" },
      { id: :default, type: "Integer" }
    ].freeze

    OPTIONAL_VALIDATIONS = [{ id: :required, type: "Boolean" }, { id: :validations, type: "Hash" }].freeze

    validates_each :label, :options do |record, key, value|
      validate_required_attributes(REQUIRED_ATTRIBUTES, record, key, value)
    end

    validates_each :description, :multiple, :default do |record, key, value|
      next if value.nil?
      validate_optional_attributes(OPTIONAL_ATTRIBUTES, record, key, value)
    end

    validates_each :validations, :required do |record, key, value|
      next if value.nil?
      validate_optional_attributes(OPTIONAL_VALIDATIONS, record, key, value)
    end

    validate :no_extra_keys
    validate :no_extra_attributes
    validate :valid_options
    validate :id_is_string
    validate :default_index_valid

    attr_reader :type, :id, :label, :description, :required, :options, :input, :multiple, :default, :validations, :auto_id

    def initialize(input:)
      @input = input
      @type = @input.dig("type")

      @options = @input.dig("attributes", "options")

      # Replace any blank values with an empty string
      @options = @options.map { |option| option.blank? ? "" : option } if @options.is_a?(Array)

      @description = @input.dig("attributes", "description")
      @label = @input.dig("attributes", "label")
      @id, @auto_id = build_id(@input, @label)
      @required = false_if_undefined(@input, "validations", "required")
      @validations = @input.dig("validations")
      @multiple = false_if_undefined(@input, "attributes", "multiple")
      @default = @input.dig("attributes", "default")
    end

    def multiple?
      multiple
    end

    def platform_type_name
      "IssueFormElementDropdown"
    end

    private

    def no_extra_attributes
      check_extraneous_attributes(REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES, @input["attributes"]&.keys)
    end

    def default_index_valid
      return unless @default.present? && @options.present?
      unless @default.is_a?(Integer)
        self.errors.add(:base, "`default` index must be an integer")
        return
      end

      self.errors.add(:base, "`default` index must be 0 or greater") if @default < 0
      self.errors.add(:base, "`default` index is larger that number of options") if @default >= @options.length
    end
  end
end
