# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::IssueType < T::Struct
  const :id, Integer
  const :name, String
  const :description, T.nilable(String)
  const :color, String

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    {
      id: id,
      name: name,
      description: description,
      color: color,
    }
  end

  sig { returns(String) }
  def to_csv
    name
  end
end
