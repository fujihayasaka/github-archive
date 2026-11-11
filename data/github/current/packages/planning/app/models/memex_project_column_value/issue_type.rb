# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::IssueType < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :id, Integer
  const :name, String
  const :description, T.nilable(String)
  const :color, String

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      id: id,
      name: name,
      description: description,
      color: color,
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
