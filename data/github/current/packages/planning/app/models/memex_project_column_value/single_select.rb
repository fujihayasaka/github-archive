# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::SingleSelect < T::Struct
  include GitHub::Memoizer
  include MemexProjectColumnValue::SerializableValue

  const :id, String
  const :name, String

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      id:,
    }
  end

  sig { override.returns(String) }
  def to_s
    name
  end

  sig { override.returns(String) }
  def to_csv
    name
  end
end
