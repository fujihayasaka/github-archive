# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::Milestone < T::Struct
  const :id, Integer
  const :number, Integer
  const :title, String
  const :state, String
  const :due_date, T.nilable(Date)
  const :url, String
  const :repo_name_with_owner, String

  sig { returns(T::Hash[T.untyped, T.untyped]) }
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

  sig { returns(String) }
  def to_csv
    title
  end
end
