# typed: strict
# frozen_string_literal: true

class IssueFieldNumberValue < IssueFieldValue
  include Issues::IIssueFieldNumberValue
  include MemexProjectColumn::IDataSource
  include GitHub::Memoizer

  require "elastomer/adapters/number_field_encoding"

  # 32-bit signed integer limits
  MAX_INTEGER_VALUE = T.let(2_147_483_647, Integer)
  MIN_INTEGER_VALUE = T.let(-2_147_483_648, Integer)

  validate :validate_number_format

  sig { returns(String) }
  def self.sti_name
    "number"
  end

  sig { override.returns(Numeric) }
  def value
    # Parse as BigDecimal for precision, then convert to appropriate numeric type
    parsed = BigDecimal(raw_value.to_s)

    # This checks if the number has no fractional part.
    # It will then return as integer if it's a whole number, otherwise as float
    if parsed.frac == 0
      parsed.to_i
    else
      parsed.to_f
    end
  end

  # Returns the formatted number string for ElasticSearch indexing
  sig { override.returns(T.nilable(String)) }
  def elasticsearch_value
    Elastomer::Adapters::NumberFieldEncoding.encode(value)
  end

  sig { override.returns(MemexProjectColumnValue::Number) }
  memoize def memex_project_column_value
    MemexProjectColumnValue::Number.new(value:)
  end

  private

  sig { void }
  def validate_number_format
    if raw_value.blank?
      errors.add(:value, "Number value can't be blank")
      return
    end

    # Convert to string for validation
    value_str = raw_value.to_s.strip

    # Check if it contains only valid numerical characters
    unless valid_number_format?(value_str)
      errors.add(:value, "must contain only numbers, decimals, and optional negative sign")
      return
    end

    # Parse the number
    begin
      parsed_number = BigDecimal(value_str)
    rescue ArgumentError, TypeError
      errors.add(:value, "must be a valid number")
      return
    end

    # Check 32-bit signed integer limits
    if parsed_number > MAX_INTEGER_VALUE
      errors.add(:value, "cannot be greater than #{MAX_INTEGER_VALUE}")
      return
    end

    if parsed_number < MIN_INTEGER_VALUE
      errors.add(:value, "cannot be less than #{MIN_INTEGER_VALUE}")
      nil
    end
  end

  # Check if the string contains only valid numerical characters:
  # - digits (0-9)
  # - decimal point (.)
  # - negative sign (-) only at the beginning
  sig { params(value_str: String).returns(T::Boolean) }
  def valid_number_format?(value_str)
    number_pattern = /\A-?\d+(\.\d+)?\z/

    value_str.match?(number_pattern)
  end
end
