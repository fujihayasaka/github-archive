# typed: strict
# frozen_string_literal: true

module Issues
  # Shared validation logic for issue field options
  # Used across REST API and HTML controller to ensure consistent validation
  # Note: GraphQL validation is handled by the schema's required fields and enum types
  module FieldOptionValidator
    # Valid color values for issue field options (shared with IssueFieldOption model)
    VALID_COLORS = T.let(IssueFieldOption::COLORS.keys.map(&:to_s).freeze, T::Array[String])

    class ValidationError < StandardError
      sig { returns(String) }
      attr_reader :message

      sig { params(message: String).void }
      def initialize(message)
        @message = message
        super(message)
      end
    end

    # Validates that required fields are present and valid in option data
    # @param options [Array<Hash>] Array of option hashes with string or symbol keys
    # @raise [ValidationError] if any option is missing required fields or has invalid values
    sig { params(options: T::Array[T::Hash[T.any(String, Symbol), T.untyped]]).void }
    def self.validate_options!(options)
      options.each_with_index do |option, index|
        option_label = "Option #{index + 1}"

        # Support both string and symbol keys
        name = option["name"] || option[:name]
        color = option["color"] || option[:color]
        priority = option["priority"] || option[:priority]

        if name.blank?
          raise ValidationError.new("#{option_label}: name is required")
        end

        if color.blank?
          raise ValidationError.new("#{option_label}: color is required")
        end

        # Validate color is a valid enum value
        color_str = color.to_s.downcase
        unless VALID_COLORS.include?(color_str)
          raise ValidationError.new("#{option_label}: color must be one of #{VALID_COLORS.join(', ')}")
        end

        if priority.nil?
          raise ValidationError.new("#{option_label}: priority is required")
        end
      end
    end
  end
end
