# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::UserValue < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :id, Integer
  const :display_login, String
  const :avatar_url, String
  const :url, String

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      avatarUrl: avatar_url,
      id: id,
      login: display_login,
      url: url,
    }
  end

  sig { override.returns(String) }
  def to_s
    display_login
  end

  sig { override.returns(String) }
  def to_csv
    display_login
  end
end
