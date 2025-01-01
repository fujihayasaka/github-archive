# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::Iteration < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :id, String
  const :title, T.nilable(String)
  const :title_html, T.nilable(String)
  const :start_date, T.nilable(String)
  const :duration, T.nilable(Integer)

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    {
      id: id,
      title: title,
      title_html: title_html,
      start_date: start_date,
      duration: duration
    }.compact.with_indifferent_access
  end

  sig { override.returns(String) }
  def to_s
    title.to_s
  end

  sig { override.returns(String) }
  def to_csv
    title.to_s
  end
end
