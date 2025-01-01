# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::UserValue < T::Struct
  const :id, Integer
  const :display_login, String
  const :avatar_url, String
  const :url, String

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    {
      avatarUrl: avatar_url,
      id: id,
      login: display_login,
      url: url,
    }
  end

  sig { returns(String) }
  def to_csv
    display_login
  end
end
