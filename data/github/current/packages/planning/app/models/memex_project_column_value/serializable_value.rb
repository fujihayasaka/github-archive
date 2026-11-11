# typed: strict
# frozen_string_literal: true

module MemexProjectColumnValue::SerializableValue
  extend T::Helpers
  abstract!

  # Redacts the model, indicating that it should not be serialized in full.
  # This is typically used when the user does not have permission to view the full model data.
  sig(:final)  { returns(T.nilable(T::Boolean)) }
  def redact!
    @redacted = T.let(true, T.nilable(T::Boolean))
  end

  # Returns true if the model should be redacted. If true we'll use the `to_redacted_hash` method
  # to serialize the model instead of the `to_hash` method.
  sig(:final)  { returns(T::Boolean) }
  def redacted?
    !!@redacted
  end

  # Returns a JSONValue based on whether or not the model is redacted. If redacted, it will call `to_redacted_hash`, otherwise it will call `to_hash`.
  sig(:final) { returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_permitted_hash
    redacted? ? to_redacted_hash : to_hash
  end

  # This module provides a common interface for serializing values of project columns in Memex.  # Returns a JSONValue containing the data that will be serialized as JSON to represent the model on the web client.
  # All keys should be in camelCase format.
  #
  # EXAMPLE:
  #
  #   class User < T::Struct
  #     include MemexProjectColumnValue::SerializableValue
  #
  #     sig { override.returns(MemexProjectColumnValue::SerializableValue::JSONValue) }
  #     def to_hash
  #       {
  #         avatarUrl: primary_avatar_url(40),
  #         id: id,
  #         login: display_login,
  #         url: permalink,
  #       }
  #     end
  #   end
  sig { abstract.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash; end

  # Returns a string representation of the value, suitable for display in the web client.
  #
  # EXAMPLE:
  #
  #   class User < T::Struct
  #     include MemexProjectColumnValue::SerializableValue
  #
  #     sig { override.returns(String) }
  #     def to_s
  #       display_login || ""
  #     end
  #   end
  #
  sig { abstract.returns(String) }
  def to_s; end

  # Returns a CSV compatible string containing data needed by the web export to render a rich representation of a column value.
  #
  # EXAMPLE:
  #
  #   class Label < T::Struct
  #     include MemexProjectColumnValue::SerializableValue
  #
  #     sig { override.returns(String) }
  #     def to_csv
  #       name || ""
  #     end
  #   end
  sig { abstract.returns(String) }
  def to_csv; end

  # Returns a JSONValue containing the redacted data that will be serialized as JSON to represent the model on the web client.
  # This hash will be used if the user does not have permission to view the full data.
  #
  # EXAMPLE:
  #
  #   class Issue < T::Struct
  #     include MemexProjectColumnValue::SerializableValue::Serializable
  #
  #     sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  #     def to_redacted_hash
  #       {
  #         id: id,
  #         title: "You do not have permission to view this issue",
  #         state: nil,
  #         stateReason: nil,
  #         url: nil,
  #       }
  #     end
  #   end
  #
  sig { overridable.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_redacted_hash
    {}
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    return false unless other.is_a?(MemexProjectColumnValue::SerializableValue)
    to_hash == other.to_hash
  end
end
