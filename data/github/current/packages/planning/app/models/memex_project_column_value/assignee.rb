# typed: strict
# frozen_string_literal: true

# Serializes a user and include their profile name. For use when the User's :profile association has been prefilled.
class MemexProjectColumnValue::Assignee < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :user_value, MemexProjectColumnValue::UserValue
  const :profile_name, T.nilable(String)
  const :include_name, T::Boolean, default: false

  sig { returns(T::Boolean) }
  def include_name?
    include_name
  end

  delegate :id, :display_login, :avatar_url, :url, :to_s, :to_csv, to: :user_value

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    # Serialize the property as :name to match frontend types when requested
    return user_value.to_hash unless include_name?

    user_value.to_hash.merge(name: profile_name)
  end
end
