# typed: true
# frozen_string_literal: true

module StructuredTemplates
  # In the event that an invalid `type` is in a TemplateConfig input, an instance of this class is used as a placeholder
  class InputBase
    include ActiveModel::Validations

    VALID_INPUT_TYPES = %w[
      checkboxes
      markdown
      dropdown
      input
      textarea
    ].freeze
    USER_INPUT_TYPES = %w[input textarea dropdown checkboxes].freeze

    attr_reader :type

    def initialize(input:)
      @input = input
      @type = @input.dig("type")
    end

    def self.create_from_input_hash(input_hash)
      type = input_hash["type"]
      if self.valid_input_type?(type)
        class_name = "StructuredTemplates::#{type.camelize}"
        class_name.constantize.new(input: input_hash)
      else
        new(input: input_hash)
      end
    end

    def self.valid_input_type?(type)
      type && VALID_INPUT_TYPES.include?(type)
    end

    def self.user_input_type?(type)
      type && USER_INPUT_TYPES.include?(type)
    end

    def required
      false
    end
  end
end
