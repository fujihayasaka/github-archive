# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::Milestone < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :id, Integer
  const :number, Integer
  const :title, String
  const :state, String
  const :due_date, T.nilable(Date)
  const :url, String
  const :repo_name_with_owner, String

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      id: id,
      number: number,
      state: state,
      title: title,
      url: url,
      dueDate: due_date,
      repoNameWithOwner: repo_name_with_owner,
    }
  end

  sig { override.returns(String) }
  def to_s
    title
  end

  sig { override.returns(String) }
  def to_csv
    title
  end
end
