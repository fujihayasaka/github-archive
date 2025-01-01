# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::Reviewer < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :type, String
  const :status, T.any(NilClass, Symbol, String)
  const :reviewer, MemexProjectColumn::IDataSource::JSONValue

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      type: type,
      status: status,
      reviewer: reviewer,
    }
  end

  sig { override.returns(String) }
  def to_s
    reviewer[:name]
  end

  sig { override.returns(String) }
  def to_csv
    reviewer[:name]
  end
end
