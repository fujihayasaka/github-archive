# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::LinkedPullRequest < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :id, Integer
  const :number, Integer
  const :is_draft, T::Boolean
  const :state, String
  const :url, T.nilable(String)

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      id: id,
      number: number,
      isDraft: is_draft,
      state: state,
      url: url,
    }
  end

  sig { override.returns(String) }
  def to_s
    url || ""
  end

  sig { override.returns(String) }
  def to_csv
    url || ""
  end
end
