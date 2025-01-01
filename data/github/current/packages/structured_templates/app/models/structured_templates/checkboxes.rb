# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class Checkboxes < InputBase
    include ActiveModel::Validations
    include StructuredTemplates::ValidationHelpers

    REQUIRED_ATTRIBUTES = [
      { id: :options, type: "Array", array_of: "Hash" },
      { id: :label, type: "String" },
    ].freeze

    OPTIONAL_ATTRIBUTES = [
      { id: :description, type: "String" },
    ].freeze

    validates_each :label, :options do |record, key, value|
      validate_required_attributes(REQUIRED_ATTRIBUTES, record, key, value)
    end

    validates_each :description do |record, key, value|
      next if value.nil?
      validate_optional_attributes(OPTIONAL_ATTRIBUTES, record, key, value)
    end

    validate :ensure_valid_checkboxes
    validate :ensure_unique_options
    validate :no_extra_keys
    validate :no_extra_attributes
    validate :id_is_string

    attr_reader :type, :id, :label, :description, :options, :input, :auto_id

    def initialize(input:)
      @input = input
      @type = @input.dig("type")
      @label = @input.dig("attributes", "label")
      @id, @auto_id = build_id(@input, @label)
      @description = @input.dig("attributes", "description")
      @options = @input.dig("attributes", "options")
    end

    def checkboxes
      return [] unless options.is_a?(Array)
      return [] if options.detect { |o| !o.is_a?(Hash) }

      @checkboxes ||= options.map do |choice|
        StructuredTemplates::Checkbox.new(input: choice)
      end
    end

    def nested_ids
      @nested_ids ||= checkboxes.map(&:id)
    end

    def platform_type_name
      "IssueFormElementCheckboxes"
    end

    private

    def no_extra_attributes
      check_extraneous_attributes(REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES, @input["attributes"]&.keys)
    end

    def ensure_valid_checkboxes
      checkboxes.map.with_index do |checkbox, index|
        unless checkbox.valid?
          checkbox.errors.each { |e| errors.add :base, "options[#{index}]: #{e.message}", docs: e.options[:docs] }
        end
      end
    end

    def ensure_unique_options
      labels = checkboxes.map(&:label)
      unless labels.uniq == labels
        errors.add :base, "`options` must be unique", docs: "#{StructuredTemplates::ConfigurationBase::DOCS_URL}#options-must-be-unique"
      end
    end
  end
end
