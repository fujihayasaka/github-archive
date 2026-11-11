# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  class PropertyLimits
    # Max length of property values
    MAX_PROPERTY_VALUE_LENGTH = 75
    private_constant :MAX_PROPERTY_VALUE_LENGTH

    # Max length of url property values
    MAX_URL_PROPERTY_VALUE_LENGTH = 200
    private_constant :MAX_URL_PROPERTY_VALUE_LENGTH

    # Max number of allowed values for select-type properties
    MAX_ALLOWED_VALUES_COUNT = 200
    private_constant :MAX_ALLOWED_VALUES_COUNT

    sig { returns(Integer) }
    attr_reader :max_property_value_length

    sig { returns(Integer) }
    attr_reader :max_url_property_value_length

    sig { returns(Integer) }
    attr_reader :max_allowed_values_count

    sig do
      params(
        max_property_value_length: Integer,
        max_allowed_values_count: Integer
      ).void
    end
    def initialize(
      max_property_value_length: MAX_PROPERTY_VALUE_LENGTH,
      max_allowed_values_count: MAX_ALLOWED_VALUES_COUNT
    )
      @max_property_value_length = T.let(max_property_value_length, Integer)
      @max_url_property_value_length = T.let(MAX_URL_PROPERTY_VALUE_LENGTH, Integer)
      @max_allowed_values_count = T.let(max_allowed_values_count, Integer)
    end

    sig { params(value_type: String).returns(Integer) }
    def max_property_value_length_by_type(value_type)
      case value_type
      when "url"
        @max_url_property_value_length
      else
        @max_property_value_length
      end
    end
  end
end
