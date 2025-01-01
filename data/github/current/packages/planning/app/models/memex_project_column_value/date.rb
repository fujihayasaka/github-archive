# typed: strict
# frozen_string_literal: true

# Represents a raw string timestamp in a project column, with no specific date parsing or formatting.
class MemexProjectColumnValue::Date < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :value, String

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      value:
    }
  end

  sig { override.returns(String) }
  def to_s
    value
  end

  sig { override.returns(String) }
  def to_csv
    value
  end
end
