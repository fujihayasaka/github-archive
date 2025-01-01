# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::LinkedPullRequest < T::Struct
  const :id, Integer
  const :number, Integer
  const :is_draft, T::Boolean
  const :state, String
  const :url, T.nilable(String)

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    {
      id: id,
      number: number,
      isDraft: is_draft,
      state: state,
      url: url,
    }
  end

  sig { returns(String) }
  def to_csv
    url || ""
  end
end
