# typed: strict
# frozen_string_literal: true

# Value object for serializing date-time values from content fields (created_at, updated_at, closed_at).
class MemexProjectColumnValue::DateTimeValue < T::Struct
  include MemexProjectColumnValue::SerializableValue
  include MemexProjectColumn::IDataSource

  const :value, String

  sig { override.returns(MemexProjectColumnValue::SerializableValue) }
  def memex_project_column_value
    self
  end

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      value: value,
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
