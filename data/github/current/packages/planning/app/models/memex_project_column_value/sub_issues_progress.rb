# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::SubIssuesProgress < T::Struct
  const :total, Integer
  const :completed, Integer
  const :percent_completed, Integer

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    {
      total: total,
      completed: completed,
      percentCompleted: percent_completed,
    }
  end

  sig { returns(String) }
  def to_csv
    "#{percent_completed}%"
  end
end
