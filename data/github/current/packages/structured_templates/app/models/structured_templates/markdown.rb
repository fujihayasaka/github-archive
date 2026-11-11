# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class Markdown < InputBase
    include ActiveModel::Validations
    include StructuredTemplates::ValidationHelpers

    REQUIRED_ATTRIBUTES = [{ id: :value, type: "String" }].freeze

    validates_each :value do |record, key, value|
      validate_required_attributes(REQUIRED_ATTRIBUTES, record, key, value)
    end

    validate :no_extra_keys
    validate :no_extra_attributes

    attr_reader :type, :value, :input

    def initialize(input:)
      @input = input
      @type = @input.dig("type")
      @value = @input.dig("attributes", "value")
    end

    def platform_type_name
      "IssueFormElementMarkdown"
    end

    def id
      nil
    end

    private

    def no_extra_attributes
      check_extraneous_attributes(REQUIRED_ATTRIBUTES, @input["attributes"]&.keys)
    end
  end
end
