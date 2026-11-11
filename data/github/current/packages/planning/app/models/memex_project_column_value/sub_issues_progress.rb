# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::SubIssuesProgress < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :total, Integer
  const :completed, Integer
  const :percent_completed, Integer

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      total: total,
      completed: completed,
      percentCompleted: percent_completed,
    }
  end

  sig { override.returns(String) }
  def to_s
    percent_completed.to_s
  end

  sig { override.returns(String) }
  def to_csv
    "#{percent_completed}%"
  end
end
