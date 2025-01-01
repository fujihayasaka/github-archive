# typed: strict
# frozen_string_literal: true

# Represents a number value in a project column.
class MemexProjectColumnValue::Number < T::Struct
  include MemexProjectColumnValue::SerializableValue
  include ActionView::Helpers::NumberHelper
  include GitHub::Memoizer

  const :value, T.any(Numeric, Integer, Float, String)

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      value: (JSON.parse(formatted_value) rescue 0)
    }
  end

  sig { override.returns(String) }
  def to_s
    formatted_value
  end

  sig { override.returns(String) }
  def to_csv
    formatted_value
  end

  private

  sig { returns(String) }
  memoize def formatted_value
    number_with_precision(value, strip_insignificant_zeros: true, precision: MemexProjectColumnValue::NUMBER_VALUE_PRECISION, raise: false)
  end
end
